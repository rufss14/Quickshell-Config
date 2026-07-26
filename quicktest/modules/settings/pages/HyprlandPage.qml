pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── HyprlandPage ────────────────────────────────────────────────────────────────
// Keybinds and compositor tuning, read from and written to the user's native-Lua
// Hyprland config (~/.config/hypr) through the HyprConfig service.
//
// Everything here is a VIEW over HyprConfig — the page is torn down and rebuilt every
// time you leave and return (SettingsCard's Loader), so it holds no durable state; the
// service owns the parsed config, the write queue, the backups and the undo stack.
//
// ── Two panes ───────────────────────────────────────────────────────────────────
// Keybinds on the left (the star, and the one thing hyprctl can't show), the tunable
// settings on the right (appearance/blur, input, animations). Edits are written to
// disk immediately — each one backed up and syntax-checked by the script — but NOT
// applied to the running session until the user presses Apply, which runs a single
// `hyprctl reload`. That split is deliberate: writing a file is cheap and reversible,
// reloading the compositor is neither, so it stays one explicit action.
Item {
    id: root

    Component.onCompleted: HyprConfig.acquire()
    Component.onDestruction: HyprConfig.release()

    // ── Keybind view state (page-local; the edits themselves go to the service) ──
    property string search: ""
    property int    editingLine: -1
    property string editCombo: ""
    property string editOrigCombo: ""
    property string editAction: ""
    property string editOrigAction: ""
    property bool   editExec: true

    property bool   adding: false
    property string addCombo: ""
    property string addValue: ""
    property bool   addLua: false

    function startEdit(b) {
        root.adding = false
        root.editingLine   = b.line
        root.editOrigCombo = b.combo
        root.editCombo     = b.combo
        root.editExec      = (b.action.type === "exec")
        root.editAction    = root.editExec
            ? b.action.args
            : ("hl.dsp." + b.action.name + "(" + (b.action.args || "") + ")")
        root.editOrigAction = root.editAction
    }
    function saveEdit(line) {
        const combo = root.editCombo.trim()
        if (combo !== "" && combo !== root.editOrigCombo)
            HyprConfig.rebind(line, combo)
        const act = root.editAction.trim()
        if (act !== "" && act !== root.editOrigAction)
            HyprConfig.setAction(line, root.editExec ? "exec" : "raw", act)
        root.editingLine = -1
    }
    function startAdd() {
        root.editingLine = -1
        root.adding = true
        root.addCombo = ""; root.addValue = ""; root.addLua = false
    }
    function saveAdd() {
        const c = root.addCombo.trim(), v = root.addValue.trim()
        if (c === "" || v === "") return
        HyprConfig.addBind(c, root.addLua ? "raw" : "exec", v)
        root.adding = false
    }

    // Binds grouped by their source section, filtered by the search box.
    readonly property var groups: {
        const s = root.search.trim().toLowerCase()
        const out = [], byName = ({})
        for (const b of HyprConfig.binds) {
            if (s !== "" &&
                !((b.combo || "").toLowerCase().includes(s)
                  || (b.action.text || "").toLowerCase().includes(s)
                  || (b.section || "").toLowerCase().includes(s)))
                continue
            const key = b.section || "Other"
            let g = byName[key]
            if (!g) { g = { section: key, binds: [] }; byName[key] = g; out.push(g) }
            g.binds.push(b)
        }
        return out
    }

    // ── Small building blocks ───────────────────────────────────────────────────
    component Field: Surface {
        id: fld
        property alias text: ti.text
        property string placeholder: ""
        property bool mono: false
        signal accepted()
        implicitHeight: 32
        elevation:    Tokens.elevationNested
        cornerRadius: Tokens.radiusSm
        focused:      ti.activeFocus
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin:  Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Colors.fg
            selectionColor: Colors.alpha(Colors.focus, 0.28)
            selectedTextColor: Colors.fg
            font.family:    fld.mono ? Tokens.fontMono : Tokens.fontFamily
            font.pixelSize: Tokens.fontBody
            onAccepted: fld.accepted()
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: ti.text === ""
                text: fld.placeholder
                emphasis: "dim"
            }
        }
    }

    // A labelled numeric slider bound to a settings key. Writes on RELEASE only —
    // each write spawns the script (a backup + a syntax check), so committing per
    // drag-pixel would be a process storm. `from` lets a range start below zero
    // (mouse sensitivity is −1..1); the slider itself is always 0..(to−from).
    component SliderRow: RowLayout {
        id: sr
        property string label
        property string skey
        property string group: "appearance"
        property real from: 0
        property real to: 1
        property bool isFloat: false
        property int decimals: 0
        property string suffix: ""
        readonly property var desc:
            (sr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[sr.skey] ?? null
        readonly property real cfgValue: sr.desc ? Number(sr.desc.value) : 0
        property real draft: 0
        onCfgValueChanged: if (!slider.pressed) sr.draft = sr.cfgValue
        Component.onCompleted: sr.draft = sr.cfgValue
        Layout.fillWidth: true
        spacing: Tokens.spacingMd
        enabled: sr.desc !== null
        function _commit() {
            if (!sr.desc) return
            const v = sr.isFloat ? Number(sr.draft.toFixed(sr.decimals)) : Math.round(sr.draft)
            HyprConfig.setValue(sr.desc.file, sr.desc.line, sr.skey, sr.isFloat ? "float" : "int", v)
        }
        StyledText {
            text: sr.label; Layout.preferredWidth: 116
            variant: "label"; emphasis: "muted"; elide: Text.ElideRight
        }
        ValueSlider {
            id: slider
            Layout.fillWidth: true
            maximum: sr.to - sr.from
            value:   sr.draft - sr.from
            onMoved: sr.draft = sr.from + value
            onScrolled: function(d) {
                sr.draft = Math.max(sr.from, Math.min(sr.to,
                    sr.draft + d * (sr.isFloat ? Math.pow(10, -sr.decimals) : 1)))
                sr._commit()
            }
            onPressedChanged: if (!pressed) sr._commit()
        }
        StyledText {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: (sr.isFloat ? sr.draft.toFixed(sr.decimals) : Math.round(sr.draft)) + sr.suffix
            variant: "label"
        }
    }

    component ToggleRow: RowLayout {
        id: tr
        property string label
        property string skey
        property string group: "appearance"
        property string kind: "bool"     // "bool" or "int" (0/1)
        readonly property var desc:
            (tr.group === "appearance" ? HyprConfig.appearance : HyprConfig.input)[tr.skey] ?? null
        readonly property bool on: tr.kind === "bool"
            ? (tr.desc ? tr.desc.value === true : false)
            : (tr.desc ? Number(tr.desc.value) !== 0 : false)
        Layout.fillWidth: true
        enabled: tr.desc !== null
        StyledText { text: tr.label; Layout.fillWidth: true; variant: "label"; emphasis: "muted" }
        Toggle {
            checked: tr.on
            onToggled: {
                if (!tr.desc) return
                const nv = tr.kind === "bool" ? (!tr.on) : (tr.on ? 0 : 1)
                HyprConfig.setValue(tr.desc.file, tr.desc.line, tr.skey, tr.kind, nv)
            }
        }
    }

    component AnimRow: RowLayout {
        id: ar
        required property var anim
        Layout.fillWidth: true
        spacing: Tokens.spacingMd
        property real draft: 0
        Component.onCompleted: ar.draft = ar.anim.speed
        StyledText {
            text: ar.anim.leaf; Layout.preferredWidth: 96
            variant: "label"; emphasis: ar.anim.enabled ? "muted" : "dim"; elide: Text.ElideRight
        }
        ValueSlider {
            Layout.fillWidth: true
            enabled: ar.anim.enabled
            maximum: 30
            value: ar.draft
            onMoved: ar.draft = value
            onPressedChanged: if (!pressed) HyprConfig.setAnim(ar.anim.line, "speed", Number(ar.draft.toFixed(1)))
        }
        StyledText {
            Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight
            text: ar.draft.toFixed(1); variant: "label"
        }
        Toggle {
            checked: ar.anim.enabled
            onToggled: HyprConfig.setAnim(ar.anim.line, "enabled", !ar.anim.enabled)
        }
    }

    // ── Layout ──────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     ""
            title:     "Hyprland"
            subtitle:  "Keybinds and tuning — writes ~/.config/hypr, applied on reload"
        }

        // ── Save / apply banner ───────────────────────────────────────────────
        // Appears once anything has been written to disk. The write already happened
        // (and was backed up); this is the one control that touches the live session.
        Surface {
            Layout.fillWidth: true
            implicitHeight: 40
            visible: HyprConfig.pendingApply || HyprConfig.canUndo
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingLg
                anchors.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingMd
                StyledText {
                    Layout.fillWidth: true
                    variant: "label"
                    text: HyprConfig.applying ? "Reloading Hyprland…"
                        : HyprConfig.pendingApply ? "Saved to disk (backed up). Reload to apply to this session."
                        : "Nothing to apply."
                    emphasis: "muted"; elide: Text.ElideRight
                }
                IconButton {
                    glyph: "󰕌"; label: "Undo"; container: true
                    visible: HyprConfig.canUndo
                    onClicked: HyprConfig.undo()
                }
                IconButton {
                    glyph: "󰑐"; label: "Apply"; container: true
                    accent: Colors.focus
                    active: true
                    visible: HyprConfig.pendingApply
                    onClicked: HyprConfig.apply()
                }
            }
        }

        // ── Error banner ──────────────────────────────────────────────────────
        Surface {
            Layout.fillWidth: true
            implicitHeight: 36
            visible: HyprConfig.lastError !== ""
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            color: Colors.alpha(Colors.danger, 0.14)
            border.color: Colors.alpha(Colors.danger, 0.4)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingLg
                anchors.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingMd
                StyledText {
                    Layout.fillWidth: true; variant: "label"
                    text: "Edit rejected — your config was left untouched: " + HyprConfig.lastError
                    color: Colors.danger; elide: Text.ElideRight
                }
                IconButton { glyph: "󰅖"; container: false; onClicked: HyprConfig.clearError() }
            }
        }

        Divider {}

        // ── Loading placeholder ───────────────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            visible: !HyprConfig.loaded
            text: "Reading ~/.config/hypr…"
            emphasis: "dim"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: HyprConfig.loaded
            spacing: Tokens.spacingXl

            // ══ LEFT: keybinds ═══════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    Field {
                        Layout.fillWidth: true
                        placeholder: "Search keybinds…"
                        onTextChanged: root.search = text
                    }
                    IconButton { glyph: "󰐕"; label: "Add"; container: true; onClicked: root.startAdd() }
                }

                // ── Add form ──────────────────────────────────────────────
                Surface {
                    Layout.fillWidth: true
                    visible: root.adding
                    onVisibleChanged: if (visible) { addComboField.text = ""; addValueField.text = "" }
                    implicitHeight: addCol.implicitHeight + Tokens.spacingLg * 2
                    elevation:    Tokens.elevationNested
                    cornerRadius: Tokens.radiusSm
                    ColumnLayout {
                        id: addCol
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd
                            Field {
                                id: addComboField
                                Layout.preferredWidth: 160
                                placeholder: "SUPER + B"; mono: true
                                onTextChanged: root.addCombo = text
                            }
                            Field {
                                id: addValueField
                                Layout.fillWidth: true
                                placeholder: root.addLua ? "hl.dsp.focus({ direction = \"left\" })" : "command to run"
                                mono: root.addLua
                                onTextChanged: root.addValue = text
                                onAccepted: root.saveAdd()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd
                            StyledText { text: "Lua action"; variant: "caption"; emphasis: "muted" }
                            Toggle { checked: root.addLua; onToggled: root.addLua = !root.addLua }
                            Item { Layout.fillWidth: true }
                            IconButton { glyph: "󰅖"; container: false; onClicked: root.adding = false }
                            IconButton { glyph: "󰄬"; container: true; accent: Colors.focus; active: true; onClicked: root.saveAdd() }
                        }
                    }
                }

                // ── Bind list ─────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Flickable {
                        id: bindFlick
                        anchors.fill: parent
                        contentHeight: bindCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: bindCol
                            width: bindFlick.width
                            spacing: Tokens.spacingLg

                            Repeater {
                                model: root.groups
                                Column {
                                    id: grp
                                    required property var modelData
                                    width: bindCol.width
                                    spacing: Tokens.spacingXs

                                    StyledText {
                                        text: grp.modelData.section
                                        variant: "label"; emphasis: "muted"
                                    }

                                    Repeater {
                                        model: grp.modelData.binds
                                        Column {
                                            id: bindItem
                                            required property var modelData
                                            width: grp.width
                                            readonly property bool editing:
                                                root.editingLine === bindItem.modelData.line
                                                && bindItem.modelData.editable

                                            // The row
                                            Rectangle {
                                                width: parent.width
                                                height: 38
                                                radius: Tokens.radiusSm
                                                color: rowHover.hovered ? Colors.alpha(Colors.fg, 0.05) : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin:  Tokens.spacingSm
                                                    anchors.rightMargin: Tokens.spacingSm
                                                    spacing: Tokens.spacingMd
                                                    // Combo chip
                                                    Rectangle {
                                                        Layout.preferredWidth: comboText.implicitWidth + Tokens.spacingMd * 2
                                                        Layout.preferredHeight: 24
                                                        radius: Tokens.radiusSm
                                                        color: Colors.alpha(Colors.focus, 0.14)
                                                        border.width: Tokens.borderWidth
                                                        border.color: Colors.alpha(Colors.focus, 0.28)
                                                        StyledText {
                                                            id: comboText
                                                            anchors.centerIn: parent
                                                            text: bindItem.modelData.combo
                                                            variant: "caption"
                                                            font.family: Tokens.fontMono
                                                        }
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: bindItem.modelData.action.text
                                                             + (bindItem.modelData.desc ? "  ·  " + bindItem.modelData.desc : "")
                                                        variant: "label"; elide: Text.ElideRight
                                                    }
                                                    // Read-only marker — the action text
                                                    // already says why (a loop range, or a
                                                    // custom Lua function).
                                                    StyledText {
                                                        visible: !bindItem.modelData.editable
                                                        text: "󰌾"
                                                        variant: "label"; emphasis: "dim"
                                                    }
                                                    IconButton {
                                                        visible: bindItem.modelData.editable && (rowHover.hovered || bindItem.editing)
                                                        glyph: "󰏫"; container: false
                                                        onClicked: root.startEdit(bindItem.modelData)
                                                    }
                                                    IconButton {
                                                        visible: bindItem.modelData.editable && rowHover.hovered
                                                        glyph: "󰆴"; container: false
                                                        iconColor: Colors.danger
                                                        onClicked: HyprConfig.removeBind(bindItem.modelData.line)
                                                    }
                                                }
                                                HoverHandler { id: rowHover }
                                            }

                                            // Inline editor. Fields are SEEDED when the
                                            // editor becomes visible rather than bound to
                                            // root.editCombo/Action — a live binding is
                                            // broken by the first keystroke and would then
                                            // show stale text if the same row is reopened.
                                            Surface {
                                                width: parent.width
                                                visible: bindItem.editing
                                                onVisibleChanged: if (visible) {
                                                    comboField.text = root.editCombo
                                                    actionField.text = root.editAction
                                                }
                                                implicitHeight: bindItem.editing ? editCol.implicitHeight + Tokens.spacingLg * 2 : 0
                                                elevation:    Tokens.elevationNested
                                                cornerRadius: Tokens.radiusSm
                                                ColumnLayout {
                                                    id: editCol
                                                    anchors.fill: parent
                                                    anchors.margins: Tokens.spacingLg
                                                    spacing: Tokens.spacingSm
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Tokens.spacingMd
                                                        StyledText { text: "Keys"; Layout.preferredWidth: 46; variant: "caption"; emphasis: "muted" }
                                                        Field {
                                                            id: comboField
                                                            Layout.fillWidth: true; mono: true
                                                            onTextChanged: root.editCombo = text
                                                        }
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Tokens.spacingMd
                                                        StyledText {
                                                            text: root.editExec ? "Run" : "Lua"
                                                            Layout.preferredWidth: 46; variant: "caption"; emphasis: "muted"
                                                        }
                                                        Field {
                                                            id: actionField
                                                            Layout.fillWidth: true
                                                            mono: !root.editExec
                                                            onTextChanged: root.editAction = text
                                                            onAccepted: root.saveEdit(bindItem.modelData.line)
                                                        }
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Item { Layout.fillWidth: true }
                                                        IconButton { glyph: "󰅖"; container: false; onClicked: root.editingLine = -1 }
                                                        IconButton {
                                                            glyph: "󰄬"; container: true; accent: Colors.focus; active: true
                                                            onClicked: root.saveEdit(bindItem.modelData.line)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Scrollbar { flickable: bindFlick }
                }
            }

            // ══ RIGHT: settings ══════════════════════════════════════════════
            Item {
                Layout.preferredWidth: 372
                Layout.fillHeight: true
                Flickable {
                    id: setFlick
                    anchors.fill: parent
                    contentHeight: setCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: setCol
                        width: setFlick.width
                        spacing: Tokens.spacingLg

                        // Appearance & blur
                        Surface {
                            Layout.fillWidth: true
                            implicitHeight: appCol.implicitHeight + Tokens.spacingLg * 2
                            elevation: Tokens.elevationNested
                            cornerRadius: Tokens.radiusSm
                            ColumnLayout {
                                id: appCol
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingLg
                                spacing: Tokens.spacingSm
                                StyledText { text: "Appearance & blur"; variant: "label"; font.weight: Font.DemiBold }
                                SliderRow { label: "Inner gaps";  skey: "gaps_in";      to: 40; suffix: "px" }
                                SliderRow { label: "Outer gaps";  skey: "gaps_out";     to: 60; suffix: "px" }
                                SliderRow { label: "Border size"; skey: "border_size";  to: 8;  suffix: "px" }
                                SliderRow { label: "Rounding";    skey: "rounding";     to: 30; suffix: "px" }
                                SliderRow { label: "Active";      skey: "active_opacity";   to: 1; isFloat: true; decimals: 2 }
                                SliderRow { label: "Inactive";    skey: "inactive_opacity"; to: 1; isFloat: true; decimals: 2 }
                                Divider {}
                                ToggleRow { label: "Shadow"; skey: "shadow_enabled" }
                                ToggleRow { label: "Blur";   skey: "blur_enabled" }
                                SliderRow { label: "Blur size";    skey: "blur_size";    to: 20 }
                                SliderRow { label: "Blur passes";  skey: "blur_passes";  from: 1; to: 5 }
                                SliderRow { label: "Vibrancy";     skey: "blur_vibrancy"; to: 1; isFloat: true; decimals: 2 }
                            }
                        }

                        // Input
                        Surface {
                            Layout.fillWidth: true
                            implicitHeight: inpCol.implicitHeight + Tokens.spacingLg * 2
                            elevation: Tokens.elevationNested
                            cornerRadius: Tokens.radiusSm
                            ColumnLayout {
                                id: inpCol
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingLg
                                spacing: Tokens.spacingSm
                                StyledText { text: "Input"; variant: "label"; font.weight: Font.DemiBold }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacingMd
                                    StyledText { text: "Layouts"; Layout.preferredWidth: 116; variant: "label"; emphasis: "muted" }
                                    Field {
                                        Layout.fillWidth: true; mono: true
                                        text: HyprConfig.input.kb_layout ? HyprConfig.input.kb_layout.value : ""
                                        onAccepted: {
                                            const d = HyprConfig.input.kb_layout
                                            if (d) HyprConfig.setValue(d.file, d.line, "kb_layout", "str", text)
                                        }
                                    }
                                }
                                SliderRow { label: "Sensitivity"; group: "input"; skey: "sensitivity"; from: -1; to: 1; isFloat: true; decimals: 2 }
                                ToggleRow { label: "Focus follows mouse"; group: "input"; skey: "follow_mouse"; kind: "int" }
                                ToggleRow { label: "Natural scroll"; group: "input"; skey: "natural_scroll" }
                            }
                        }

                        // Animations
                        Surface {
                            Layout.fillWidth: true
                            implicitHeight: anCol.implicitHeight + Tokens.spacingLg * 2
                            elevation: Tokens.elevationNested
                            cornerRadius: Tokens.radiusSm
                            ColumnLayout {
                                id: anCol
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingLg
                                spacing: Tokens.spacingSm
                                StyledText { text: "Animations"; variant: "label"; font.weight: Font.DemiBold }
                                Repeater {
                                    model: HyprConfig.animations
                                    AnimRow { required property var modelData; anim: modelData }
                                }
                            }
                        }
                    }
                }
                Scrollbar { flickable: setFlick }
            }
        }
    }
}
