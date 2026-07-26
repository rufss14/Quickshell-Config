pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import ".."

// ── BarPage ───────────────────────────────────────────────────────────────────
// Everything about the bar that a person actually changes: what's on it, where, how
// thick, how round, how far off the edge.
//
// It writes straight to Config and never keeps a copy. There is no Apply button and no
// pending-changes state, because the bar is on screen a few hundred pixels away while
// you drag the slider — the preview IS the bar. An Apply step would mean mirroring
// every value here and reconciling the two, to buy a confirmation nobody asked for on a
// change you can already see and undo.
//
// ── Two columns ───────────────────────────────────────────────────────────────
// Appearance and layout are independent — you come here to do one or the other — and
// the layout editor needs real width to drag in. So: a fixed column of controls, and
// the editor taking everything else.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Which preset is being renamed, by name, or "" for none. One at a time — the name is
    // the identity here, so two open editors could be racing for the same one.
    property string renaming: ""

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        PanelHeader {
            glyph:     "󰍜"
            title:     "Bar"
            titleTail: "layout"
            subtitle:  "Drag a module onto another to group them"

            PanelButton {
                label: "Reset"
                glyph: "󰑐"
                onActivated: Config.resetBar()
            }
        }

        Divider {}

        // ── The bar, here, because you can't see the real one ─────────────────
        // The overview covers the screen and Hyprland blurs what's behind it, so the
        // surface being edited is the one surface that isn't visible while you edit it.
        // This is the same BarRegion/BarGroup/widgets reading the same Config.layout —
        // not a drawing of a bar, the bar.
        BarPreview {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            // Clicking a module in the preview is the same act as clicking its chip —
            // both just point the inspector at it.
            onModuleActivated: id => layoutEditor.focusId = id
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacingXs
            spacing: Tokens.spacingXl

            // ══ Controls ══════════════════════════════════════════════════════
            // Scrolls, because it no longer fits: five sections come to roughly 870px
            // against a 640px card, so the Presets box at the bottom sat below the fold
            // with no way to reach it. Same Flickable the About page uses.
            //
            // Only THIS column scrolls. The layout editor beside it is a drag target —
            // a surface that slid while you were dragging a module onto it would move
            // the drop you were aiming at.
            //
            // ValueSlider owns a MouseArea with an onWheel, which accepts the event, so
            // the wheel still adjusts a slider you are pointing at rather than scrolling
            // the column out from under it.
            Flickable {
                Layout.preferredWidth: 300
                Layout.minimumWidth:   300
                Layout.maximumWidth:   300
                Layout.fillHeight: true

                clip: true
                contentHeight: controls.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: controls
                    width: parent.width
                    spacing: Tokens.spacingMd

                    StyledText { text: "Shape"; variant: "label"; emphasis: "muted" }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: shapeBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: shapeBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            SettingRow {
                                label:  "Square corners"
                                detail: "Flush to the screen edges"
                                Toggle {
                                    checked: Config.barShape
                                    onToggled: Config.toggleShape()
                                }
                            }

                            Divider {}

                            SettingRow {
                                // Was "Merge groups" — renamed so "merge" means only one
                                // thing on this page (welding the pill to the frame,
                                // below). This is a different choice: one pill per region
                                // instead of one per group.
                                label:  "Combine groups"
                                detail: "One pill per region, not one per group"
                                Toggle {
                                    checked: Config.barMode
                                    onToggled: Config.toggleMode()
                                }
                            }

                            Divider {}

                            SettingRow {
                                label:  "Anchor on workspaces"
                                detail: Config.isPlaced("workspaces")
                                    ? "Keeps the dots on true screen centre"
                                    : "Needs the workspaces module on the bar"
                                // With workspaces off the bar there is nothing to anchor to,
                                // and the centre region already centres itself regardless —
                                // so the toggle would sit there claiming a choice it isn't
                                // making.
                                enabled: Config.isPlaced("workspaces")
                                Toggle {
                                    checked: Config.barCentreAnchor
                                    onToggled: Config.barCentreAnchor = !Config.barCentreAnchor
                                }
                            }

                            Divider {}

                            // ── Frame ──────────────────────────────────────────────────
                            // One choice, not two overlapping toggles. It used to be
                            // "Screen frame" and "Bar frame" as separate checkboxes where
                            // one silently included the other — which is exactly why
                            // "Bar frame" would go dead and unclickable the moment Screen
                            // frame was on, with no visible reason why. Same two booleans
                            // underneath (Config.screenFrame/barFrame); this is just an
                            // honest picture of the fact that only three states exist.
                            SettingRow {
                                label: "Frame"
                                detail: Config.screenFrame
                                    ? "A full ring around the desktop — band on top, strips down the sides and along the bottom"
                                    : Config.barFrame
                                        ? "Just a band above the bar, no reserved desktop space"
                                        : "No frame — pills float freely"

                                Row {
                                    spacing: Tokens.spacingSm

                                    PanelButton {
                                        label:   "None"
                                        variant: (!Config.screenFrame && !Config.barFrame) ? "primary" : "ghost"
                                        onActivated: {
                                            Config.screenFrame = false
                                            Config.barFrame    = false
                                        }
                                    }
                                    PanelButton {
                                        label:   "Bar"
                                        variant: (!Config.screenFrame && Config.barFrame) ? "primary" : "ghost"
                                        onActivated: {
                                            Config.screenFrame = false
                                            Config.barFrame    = true
                                        }
                                    }
                                    PanelButton {
                                        label:   "Screen"
                                        variant: Config.screenFrame ? "primary" : "ghost"
                                        onActivated: {
                                            Config.screenFrame = true
                                            Config.barFrame    = false
                                        }
                                    }
                                }
                            }

                            Divider {}

                            SettingRow {
                                label:  "Merge frame and pill"
                                // Independent of which frame is picked above — this only
                                // decides whether the pill welds into whichever band is
                                // showing (seam erased, flared corners) or stops short of
                                // it with a plain square top. Needs a frame to weld to,
                                // which is why it goes dead at "Frame: None" — there would
                                // be nothing here to merge into.
                                detail: (Config.screenFrame || Config.barFrame)
                                    ? (Config.frameMerge
                                        ? "Pill fuses into the band, seam erased"
                                        : "Pill sits below the band, not welded to it")
                                    : "Needs Frame set to Bar or Screen, above"
                                enabled: Config.screenFrame || Config.barFrame
                                Toggle {
                                    checked: Config.frameMerge
                                    onToggled: Config.toggleFrameMerge()
                                }
                            }

                            Divider {}

                            SettingRow {
                                label:  "Liquid glass"
                                // Names the dependency rather than hiding it: at a high
                                // opacity there is nothing behind the pill to light, so
                                // the treatment lands on what is effectively a solid
                                // surface and barely reads.
                                detail: Config.barOpacity > 0.9
                                    ? "Lit edges on the pills — lower Opacity to see it"
                                    : "Lit edges and a graded fill on the pills"
                                Toggle {
                                    checked: Config.barGlass
                                    onToggled: Config.barGlass = !Config.barGlass
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Size"
                        variant: "label"
                        emphasis: "muted"
                    }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: sizeBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: sizeBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingLg

                            SliderRow {
                                label: "Thickness"
                                from:  Config.barThicknessMin
                                to:    Config.barThicknessMax
                                value: Config.barThickness
                                onCommit: function(v) { Config.barThickness = v }
                            }

                            SliderRow {
                                label: "Roundness"
                                from:  0
                                to:    Config.barRoundnessMax
                                value: Config.barRoundness
                                // Square mode collapses every corner to 0, so the slider
                                // would sit there claiming a roundness the bar visibly
                                // doesn't have.
                                enabled: !Config.barShape
                                onCommit: function(v) { Config.barRoundness = v }
                            }

                            SliderRow {
                                label: "Edge inset"
                                from:  0
                                to:    Config.barInsetMax
                                value: Config.barInset
                                enabled: !Config.barShape
                                onCommit: function(v) { Config.barInset = v }
                            }

                            SliderRow {
                                label: "Frame thickness"
                                from:  Config.frameThicknessMin
                                to:    Config.frameThicknessMax
                                value: Config.frameThickness
                                // Without the frame there is nothing this thickness applies
                                // to — same treatment as Roundness in square mode. Merge
                                // frame and pill draws the identical band, so it counts too.
                                enabled: Config.screenFrame || Config.barFrame
                                onCommit: function(v) { Config.frameThickness = v }
                            }

                            SliderRow {
                                label: "Frame roundness"
                                from:  0
                                to:    Config.frameRoundnessMax
                                value: Config.frameRoundness
                                // The ring's INNER corner radius. Its own control now
                                // rather than a fixed derivation off thickness — the
                                // corner is the most visible part of the frame and the
                                // one number you'd actually want to tune.
                                enabled: Config.screenFrame || Config.barFrame
                                onCommit: function(v) { Config.frameRoundness = v }
                            }

                            SliderRow {
                                label: "Pill spacing"
                                from:  0
                                to:    Config.barSpacingMax
                                value: Config.barSpacing
                                // Merged mode has no gaps to space — its groups are divided
                                // inside one pill — so the slider would move nothing.
                                enabled: !Config.barMode
                                onCommit: function(v) { Config.barSpacing = v }
                            }
                        }
                    }

                    // ══ Appearance ════════════════════════════════════════════════
                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Appearance"
                        variant: "label"
                        emphasis: "muted"
                    }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: appearanceBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: appearanceBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingLg

                            SliderRow {
                                label: "Opacity"
                                from:  Config.barOpacityMin
                                to:    1.0
                                step:  0.01
                                value: Config.barOpacity
                                readout: Math.round(Config.barOpacity * 100) + "%"
                                onCommit: function(v) { Config.barOpacity = v }
                            }

                            // Only the bar's real TEXT — the clock, the layout tag, an SSID.
                            // Its glyphs are Nerd Font icons, so they follow Icon size.
                            SliderRow {
                                label: "Text size"
                                from:  Config.barScaleMin
                                to:    Config.barScaleMax
                                step:  0.05
                                value: Config.barFontScale
                                readout: Config.barFontScale.toFixed(2) + "×"
                                onCommit: function(v) { Config.barFontScale = v }
                            }

                            SliderRow {
                                label: "Icon size"
                                from:  Config.barScaleMin
                                to:    Config.barScaleMax
                                step:  0.05
                                value: Config.barIconScale
                                readout: Config.barIconScale.toFixed(2) + "×"
                                onCommit: function(v) { Config.barIconScale = v }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: Config.barOpacity < 0.95
                                text: "Opacity needs a compositor blur behind it — see the "
                                    + "layer_rule note in Bar.qml"
                                variant:  "caption"
                                emphasis: "dim"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ══ Motion ════════════════════════════════════════════════════
                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Motion"
                        variant: "label"
                        emphasis: "muted"
                    }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: motionBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: motionBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            SettingRow {
                                label:  "Animations"
                                detail: "Off makes every transition instant"
                                Toggle {
                                    checked: Config.motionEnabled
                                    onToggled: Config.motionEnabled = !Config.motionEnabled
                                }
                            }

                            Divider {}

                            SettingRow {
                                label:  "Pills grow on hover"
                                detail: "The bar's nudge when you point at a group"
                                Toggle {
                                    checked: Config.barHoverGrow
                                    onToggled: Config.barHoverGrow = !Config.barHoverGrow
                                }
                            }

                            Divider {}

                            // Scales every duration in the shell at once. Live readouts
                            // (sliders, the visualizer) are deliberately exempt — see
                            // Motion.qml.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd
                                enabled: Config.motionEnabled
                                opacity: enabled ? 1.0 : 0.4
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                StyledText {
                                    Layout.preferredWidth: 84
                                    text: "Speed"
                                    variant: "body"
                                }
                                ValueSlider {
                                    Layout.fillWidth: true
                                    maximum: 1.0
                                    value: (Config.motionScale - Config.motionScaleMin)
                                         / (Config.motionScaleMax - Config.motionScaleMin)
                                    onMoved: function(v) {
                                        Config.motionScale = Math.round((Config.motionScaleMin
                                            + v * (Config.motionScaleMax - Config.motionScaleMin)) * 20) / 20
                                    }
                                }
                                StyledText {
                                    Layout.preferredWidth: 38
                                    horizontalAlignment: Text.AlignRight
                                    // Inverted on purpose: a bigger NUMBER should mean
                                    // faster. motionScale is a duration multiplier, so 0.5×
                                    // duration is 2× speed — printing the multiplier would
                                    // put "0.5" next to the word "Speed" on the fast end.
                                    text: (1 / Config.motionScale).toFixed(1) + "×"
                                    variant:  "caption"
                                    emphasis: "dim"
                                }
                            }
                        }
                    }

                    // ══ Presets ═══════════════════════════════════════════════════
                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Presets"
                        variant: "label"
                        emphasis: "muted"
                    }

                    // Sized to its contents, like every other box here — it was pinned at
                    // 132px, which is four rows and a save bar. A fifth preset went
                    // behind the edge, and the only way to it was a scroll INSIDE a box
                    // that was itself inside the column's scroll.
                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: presetsBox.implicitHeight + Tokens.spacingMd * 2

                        ColumnLayout {
                            id: presetsBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingSm

                            ListView {
                                Layout.fillWidth: true
                                // The whole list, always. The column around it scrolls, so
                                // this doesn't have to — and `interactive: false` is what
                                // stops it eating the wheel and pinning the column in
                                // place whenever the pointer crossed the presets.
                                Layout.preferredHeight: contentHeight
                                interactive: false
                                spacing: 2
                                // allPresets, not presets: the built-in "Default" leads the
                                // list and is never stored, so it can't drift from Reset.
                                model: Config.allPresets
                                // (`boundsBehavior` removed with the scrolling — it only
                                // governs overscroll, and this can't scroll any more.)

                                delegate: Rectangle {
                                    id: presetRow
                                    required property var modelData

                                    // Recomputed against the live bar, so editing anything
                                    // after loading a preset drops the mark — the dot means
                                    // "the bar IS this", not "you clicked this once".
                                    readonly property bool active: Config.presetActive(presetRow.modelData.name)

                                    readonly property bool builtin: presetRow.modelData.builtin ?? false
                                    readonly property bool editing: root.renaming === presetRow.modelData.name
                                                                 && !presetRow.builtin
                                    // Hidden while renaming: the row is a text field then, and
                                    // a delete glyph beside the caret is a way to lose the
                                    // preset you were in the middle of naming.
                                    readonly property bool hoverActions: presetHover.hovered
                                                                      && !presetRow.builtin
                                                                      && !presetRow.editing

                                    width:  ListView.view ? ListView.view.width : 0
                                    height: 28
                                    radius: Tokens.radiusSm

                                    color: presetRow.active     ? Colors.alpha(Colors.focus, 0.14)
                                         : presetHover.hovered  ? Colors.alpha(Colors.fg, 0.06)
                                         :                        "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin:  Tokens.spacingMd
                                        anchors.rightMargin: Tokens.spacingSm
                                        spacing: Tokens.spacingSm

                                        StyledText {
                                            text:  presetRow.active ? "󰄯" : "󰝤"
                                            color: presetRow.active ? Colors.focus : Colors.fgDim
                                            variant: "caption"
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: !presetRow.editing
                                            text:    presetRow.modelData.name
                                            variant: "caption"
                                            font.weight: presetRow.active ? Font.DemiBold : Font.Normal
                                            elide:   Text.ElideRight
                                        }

                                        // ── Renaming happens in place ─────────────
                                        // The name IS the identity, so a rename is a
                                        // correction to this row rather than a trip to a
                                        // dialog. Editing where the name already is means
                                        // there's nothing to explain.
                                        TextInput {
                                            id: renameInput
                                            Layout.fillWidth: true
                                            visible: presetRow.editing
                                            text:    presetRow.modelData.name
                                            color:   Colors.fg
                                            font.family:    Tokens.fontFamily
                                            font.pixelSize: Tokens.fontCaption
                                            selectByMouse:  true
                                            selectionColor: Colors.alpha(Colors.focus, 0.35)
                                            verticalAlignment: TextInput.AlignVCenter

                                            // Re-arm on every open: the delegate is recycled,
                                            // so a stale edit would otherwise be sitting in it
                                            // the next time this row is renamed.
                                            onVisibleChanged: if (visible) {
                                                text = presetRow.modelData.name
                                                selectAll()
                                                forceActiveFocus()
                                            }

                                            function commit() {
                                                // Read before clearing: `renaming = ""` tears
                                                // this input down, and `text` goes with it.
                                                const to = renameInput.text
                                                const from = presetRow.modelData.name
                                                root.renaming = ""
                                                Config.renamePreset(from, to)
                                            }

                                            onAccepted: renameInput.commit()
                                            Keys.onEscapePressed: root.renaming = ""
                                            // Clicking away commits rather than discards —
                                            // you typed it, you meant it. A refused rename
                                            // (duplicate, or the reserved name) is a no-op in
                                            // Config, so the row just keeps its old name.
                                            onActiveFocusChanged: if (!activeFocus && presetRow.editing)
                                                renameInput.commit()
                                        }

                                        StyledText {
                                            // The built-in is computed, not stored: there is
                                            // nothing to rename.
                                            visible: presetRow.hoverActions
                                            text:    "󰏫"
                                            color:   renameHover.hovered ? Colors.focus : Colors.fgDim
                                            variant: "caption"
                                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                                            HoverHandler { id: renameHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: root.renaming = presetRow.modelData.name
                                            }
                                        }

                                        StyledText {
                                            // The built-in has no delete: a way back you can
                                            // throw away isn't one.
                                            visible: presetRow.hoverActions
                                            text:    "󰅖"
                                            color:   deleteHover.hovered ? Colors.danger : Colors.fgDim
                                            variant: "caption"
                                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                                            HoverHandler { id: deleteHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: Config.deletePreset(presetRow.modelData.name)
                                            }
                                        }
                                    }

                                    HoverHandler { id: presetHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        // The delete glyph sits inside this row, and a
                                        // TapHandler on the parent would also fire when you
                                        // hit it — loading the preset you just deleted.
                                        // Its own handler accepts the press first; this
                                        // only sees taps that missed it.
                                        //
                                        // Off while renaming for the same reason: clicking
                                        // into the field to fix a typo would otherwise load
                                        // the preset out from under you.
                                        enabled: !presetRow.editing
                                        onTapped: Config.loadPreset(presetRow.modelData.name)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                Surface {
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    elevation:    Tokens.elevationPopup
                                    cornerRadius: Tokens.radiusSm
                                    focused:      nameInput.activeFocus

                                    TextInput {
                                        id: nameInput
                                        anchors.fill: parent
                                        anchors.leftMargin:  Tokens.spacingMd
                                        anchors.rightMargin: Tokens.spacingMd
                                        verticalAlignment: TextInput.AlignVCenter

                                        color: Colors.fg
                                        selectionColor:    Colors.alpha(Colors.focus, 0.28)
                                        selectedTextColor: Colors.fg
                                        font.family:    Tokens.fontFamily
                                        font.pixelSize: Tokens.fontCaption

                                        onAccepted: saveButton.save()

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible:  nameInput.text === ""
                                            text:     "Preset name…"
                                            variant:  "caption"
                                            emphasis: "dim"
                                        }
                                    }
                                }

                                PanelButton {
                                    id: saveButton
                                    label:   "Save"
                                    variant: "primary"
                                    // Naming is the whole gesture — an unnamed preset is
                                    // one you can never pick out of the list again.
                                    enabled: nameInput.text.trim() !== ""
                                    opacity: enabled ? 1.0 : 0.4

                                    function save() {
                                        if (nameInput.text.trim() === "") return
                                        Config.savePreset(nameInput.text)
                                        nameInput.text = ""
                                    }
                                    onActivated: saveButton.save()
                                }
                            }
                        }
                    }
                }
            }

            // ══ Layout ════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                BarLayoutEditor {
                    id: layoutEditor
                    Layout.fillWidth: true
                }

                // ── The selected module ───────────────────────────────────────
                // Reserves its height rather than appearing on selection — a panel that
                // pops in and out would shove the editor around under the cursor
                // mid-drag.
                ModuleInspector {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 190
                    moduleId: layoutEditor.focusId
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    // ── SettingRow ────────────────────────────────────────────────────────────
    // Label on the left, control on the right. Declared here rather than in
    // components/ because this shape — a settings line item — exists nowhere else in
    // the shell yet. It moves out the moment a second page needs it.
    component SettingRow: RowLayout {
        id: settingRow

        property string label:  ""
        property string detail: ""

        default property alias control: controlSlot.data

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text:    settingRow.label
                variant: "body"
                elide:   Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible:  settingRow.detail !== ""
                text:     settingRow.detail
                variant:  "caption"
                emphasis: "dim"
                elide:    Text.ElideRight
            }
        }

        Item {
            id: controlSlot
            Layout.preferredWidth:  childrenRect.width
            Layout.preferredHeight: childrenRect.height
        }
    }

    // ── SliderRow ─────────────────────────────────────────────────────────────
    // ValueSlider is normalised 0..maximum and emits a real. This maps a real range onto
    // it, so ValueSlider doesn't grow a from/to/step API for one caller.
    //
    // It was integer-pixels-only with "px" welded to the readout, which is why the Speed
    // slider below is hand-rolled out of a raw ValueSlider. Opacity and the two scales
    // would have been three more copies of that same block, so `step` and `readout` are
    // the two properties that stop this component being copied instead of used. `step: 1`
    // is the integer behaviour it always had.
    component SliderRow: RowLayout {
        id: sliderRow

        property string label: ""
        property real from:  0
        property real to:    100
        property real value: 0
        property real step:  1

        // Overridable because the unit is the caller's business: px, %, ×.
        property string readout: sliderRow.value + "px"

        // No `property bool enabled` — RowLayout is an Item, which already has one, and
        // redeclaring it shadows the property QML uses to gate input. Inheriting it is
        // also what we want: Item.enabled propagates down, so `enabled: false` on the
        // row disables the slider inside it for free.

        signal commit(real v)

        // Snap to the step, then snap off the float noise. `Math.round(v / 0.05) * 0.05`
        // produces 0.7500000000000001, and toFixed in the readout would happily print it.
        function quantise(v) {
            return Math.round(Math.round(v / sliderRow.step) * sliderRow.step * 1e6) / 1e6
        }

        Layout.fillWidth: true
        spacing: Tokens.spacingMd
        opacity: sliderRow.enabled ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        StyledText {
            Layout.preferredWidth: 84
            text:    sliderRow.label
            variant: "body"
            elide:   Text.ElideRight
        }

        ValueSlider {
            Layout.fillWidth: true
            maximum: 1.0
            value: sliderRow.to > sliderRow.from
                ? (sliderRow.value - sliderRow.from) / (sliderRow.to - sliderRow.from)
                : 0

            onMoved: function(v) {
                sliderRow.commit(sliderRow.quantise(
                    sliderRow.from + v * (sliderRow.to - sliderRow.from)))
            }
            // One step per notch, not one pixel — a 0.05 scale would otherwise jump the
            // whole range on a single wheel click.
            onScrolled: function(d) {
                sliderRow.commit(Math.max(sliderRow.from, Math.min(sliderRow.to,
                    sliderRow.quantise(sliderRow.value + d * sliderRow.step))))
            }
        }

        StyledText {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text:     sliderRow.readout
            variant:  "caption"
            emphasis: "dim"
        }
    }
}
