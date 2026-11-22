pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── SchemeCard ────────────────────────────────────────────────────────────────
// One saved scheme on the Presets view, as a miniature of what it wears: ITS background for the card, its name
// in ITS text colour, its accent as the badge, a ribbon of its colours under the name. Worn by the shell, or
// loaded in the editor, the badge blooms from a disc into a cookie with a tick and the card goes rounder, on
// springs, as the source rail's choice does; the pointer leans it in, a press dips it.
//
// Under the pointer a capsule opens at the corner: put it on now, bookmark, which workspaces wear it, rename,
// remove. A bookmarked card keeps a small mark when the pointer leaves. Remove lays a Keep / Remove layer over
// the card (nothing arms in place). A press on the card loads it into the editor; a right press asks which
// workspaces wear it. A classic ships with the shell: it can be bookmarked and given workspaces, not renamed
// or removed.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: card

    required property var panel
    // Which group it stands in ("mine" | "classic"), for folding it away under its heading.
    property string group: ""
    // From the Repeater that makes it.
    required property var modelData
    required property int index
    readonly property var scheme: card.modelData

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property string cname: card.scheme.name
    readonly property bool builtin: !!card.scheme.builtin
    readonly property string key: card.builtin ? ColorScheme.sanitiseName(card.cname) : card.cname
    readonly property bool loaded: ColorScheme.loadedName === card.key
    readonly property bool worn: ColorScheme.worn === card.cname || (ColorScheme.worn !== "" && ColorScheme.worn === card.key)
    readonly property bool on: card.loaded || card.worn
    // The version for the shell's mode; a scheme that has only the other one shows that, dimmed, so it is not
    // mistaken for the real thing.
    readonly property var pick: Palette.pickVariant(card.scheme.variants, Config.themeMode)
    readonly property var shown: card.pick.palette ?? card.scheme.palette
    readonly property color bg: Palette.slotValue(card.shown, "background")
    readonly property color ink: Palette.slotValue(card.shown, "foreground")
    readonly property color accent: Palette.slotValue(card.shown, "color1")
    readonly property bool starred: Config.colorFavorites.indexOf(card.cname) >= 0
    readonly property bool matches: card.panel.presetMatches(card.cname)
    // A folded group hides its cards, unless a search is looking for them.
    readonly property bool open: !card.panel.isFolded(card.group) || card.panel.libQuery.trim() !== ""
    readonly property var wsList: ColorScheme.workspacesOf(card.cname)
    readonly property bool hasLight: !!card.scheme.variants.light
    readonly property bool hasDark: !!card.scheme.variants.dark
    property bool renaming: false
    property bool armed: false

    // The line under the name: where it is, what it holds, who wears it.
    readonly property string line: {
        const bits = []
        if (card.worn) bits.push(Translation.tr("In use"))
        else if (card.loaded) bits.push(Translation.tr("In the editor"))
        bits.push(card.hasLight && card.hasDark ? Translation.tr("Dark and light")
                : card.hasLight ? Translation.tr("Light only") : Translation.tr("Dark only"))
        if (card.wsList.length > 0) bits.push(Translation.tr("On %1").arg(card.wsList.join(" ")))
        return bits.join("  ·  ")
    }

    function beginRename() {
        card.armed = false
        card.renaming = true
        renameField.setText(card.cname)
        renameField.forceFocus()
    }
    function commitRename() {
        const v = renameField.text.trim()
        if (v !== "" && v !== card.cname) ColorScheme.renameScheme(card.cname, v)
        card.renaming = false
    }
    function putOn() {
        card.panel.holdView = true
        ColorScheme.wear(card.scheme)
        card.panel.holdView = false
    }

    visible: card.matches && card.open
    implicitHeight: Tokens.iconXl * 2 + Tokens.spacingLg

    // Cards arrive on a spring a beat after their neighbours, every time the page is shown (or a card is
    // searched back in), not once when the delegates were built behind it.
    PopIn { id: pop; active: card.panel.view === "library" && card.matches && card.open; index: card.index }

    SpringValue { id: shapeK; target: card.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
    SpringValue {
        id: lean
        target: tap.pressed ? 0.97 : hover.hovered && !card.armed ? 1.02 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    opacity: pop.opacity
    scale: lean.value * pop.scale

    ClippingRectangle {
        id: face
        anchors.fill: parent
        color: card.bg
        radius: Tokens.radiusCard + Math.max(0, shapeK.value) * (Tokens.radiusXl - Tokens.radiusCard)
        border.width: Tokens.borderWidth
        border.color: card.palette.alpha(card.ink, 0.14)

        // How far the capsule pushes the NAME in from the right as it arrives, on a spring. Only the name: the
        // line and the ribbon under it keep their whole width, so the palette never shrinks for a tool.
        property real gap: tools.shown ? tools.width : 0
        Behavior on gap { SpringAnimation { spring: 5.0; damping: 0.55; epsilon: 0.1 } }

        // ── The badge: its accent as a disc with "Aa"; worn or loaded it blooms with a tick ──
        Item {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: Tokens.spacingMd
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.iconXl + Tokens.spacingLg
            height: width
            opacity: card.pick.exact ? 1 : 0.55
            MorphShape {
                anchors.fill: parent
                shape: card.on ? "cookie9" : "circle"
                spec: Motion.springSpatialFast
                fillColor: card.accent
            }
            StyledText {
                anchors.centerIn: parent
                visible: !card.on
                text: "Aa"
                variant: "label"
                font.weight: Font.Bold
                color: Palette.readableOn(card.accent)
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: "check"
                fill: 1
                font.pixelSize: Tokens.iconLg
                color: Palette.readableOn(card.accent)
                opacity: card.on ? 1 : 0
                scale: card.on ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
            }
        }

        // ── Name, the line under it, the ribbon ──────────────────────────────
        ColumnLayout {
            anchors.left: badge.right
            anchors.leftMargin: Tokens.spacingMd
            anchors.right: parent.right
            anchors.rightMargin: Tokens.spacingMd
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacingXs
            opacity: card.renaming ? 0 : (card.pick.exact ? 1 : 0.65)
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: Math.max(0, face.gap)
                text: card.cname
                variant: "label"
                font.weight: card.on ? Font.Bold : Font.DemiBold
                color: card.ink
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: card.line
                variant: "micro"
                color: card.palette.alpha(card.ink, 0.72)
                elide: Text.ElideRight
            }
            // The palette, as a ribbon. Cells placed by arithmetic, the edges rounded to whole pixels, so no
            // hairline seams between them.
            Item {
                id: rib
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconSm - 2
                Repeater {
                    model: 15
                    delegate: Rectangle {
                        required property int index
                        x: Math.round(index * rib.width / 15)
                        width: Math.round((index + 1) * rib.width / 15) - x
                        height: rib.height
                        topLeftRadius: index === 0 ? height / 2 : 0
                        bottomLeftRadius: index === 0 ? height / 2 : 0
                        topRightRadius: index === 14 ? height / 2 : 0
                        bottomRightRadius: index === 14 ? height / 2 : 0
                        color: Palette.slotValue(card.shown, "color" + (index + 1))
                    }
                }
            }
        }

        // ── Rename in place ────────────────────────────────────────────────
        InputField {
            id: renameField
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            visible: card.renaming
            cornerRadius: implicitHeight / 2
            onAccepted: card.commitRename()
            onEditingChanged: if (!renameField.editing) card.renaming = false
            onKeyPressed: function (e) {
                if (e.key !== Qt.Key_Escape) return
                card.renaming = false
                e.accepted = true
            }
        }

        // ── A small mark for what you kept, once the pointer is away ────────
        Rectangle {
            id: mark
            readonly property bool shown: card.starred && !tools.shown && !card.armed && !card.renaming
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.spacingSm
            width: Tokens.iconLg + Tokens.spacingSm
            height: width
            radius: width / 2
            color: card.palette.alpha(card.ink, 0.14)
            opacity: mark.shown ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            MaterialIcon {
                anchors.centerIn: parent
                name: "bookmark"
                fill: 1
                font.pixelSize: Tokens.iconMd
                color: card.ink
            }
        }

        // ── The tools: a capsule under the pointer ──────────────────────────
        Rectangle {
            id: tools
            readonly property bool shown: !card.armed && !card.renaming && hover.hovered
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.spacingSm
            width: toolRow.implicitWidth + Tokens.spacingXs * 2
            height: Tokens.iconXl + Tokens.spacingXs
            radius: height / 2
            color: card.palette.alpha(card.palette.surface, 0.94)
            opacity: Math.min(1, Math.max(0, toolsK.value))
            visible: tools.shown || toolsK.value > 0.005
            scale: 0.7 + 0.3 * Math.max(0, toolsK.value)
            transformOrigin: Item.TopRight
            SpringValue { id: toolsK; target: tools.shown ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }

            Row {
                id: toolRow
                anchors.centerIn: parent
                spacing: 0
                CardTool {
                    symbol: "palette"
                    hoverTint: card.panel.accent
                    name: Translation.tr("Put it on now")
                    onActivated: card.putOn()
                }
                CardTool {
                    id: starTool
                    symbol: "bookmark"
                    filled: card.starred
                    tint: card.starred ? card.panel.accent : card.palette.fg
                    hoverTint: card.panel.accent
                    name: card.starred ? Translation.tr("Remove the bookmark") : Translation.tr("Bookmark")
                    onActivated: { Config.colorFavToggle(card.cname); starTool.bump() }
                }
                CardTool {
                    symbol: "workspaces"
                    filled: card.wsList.length > 0
                    hoverTint: card.panel.accent
                    name: Translation.tr("Choose workspaces")
                    onActivated: ColorScheme.choose(card.cname)
                }
                CardTool {
                    visible: !card.builtin
                    symbol: "edit"
                    hoverTint: card.panel.accent
                    name: Translation.tr("Rename")
                    onActivated: card.beginRename()
                }
                CardTool {
                    visible: !card.builtin
                    symbol: "close"
                    hoverTint: card.palette.danger
                    name: Translation.tr("Remove")
                    onActivated: card.armed = true
                }
            }
        }

        // ══ Remove? ════════════════════════════════════════════════════════
        // Lays a layer over the card: what will happen and two plain buttons. It swallows the card's own click, so
        // nothing loads behind it; the pointer leaving the card calls it off.
        Item {
            anchors.fill: parent
            opacity: card.armed ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            Rectangle {
                anchors.fill: parent
                color: card.palette.alpha(card.palette.surface, 0.93)
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

            RowLayout {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingLg * 2
                spacing: Tokens.spacingMd

                Item {
                    Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingSm
                    MorphShape {
                        anchors.fill: parent
                        shape: card.armed ? "squircle" : "circle"
                        spec: Motion.springSpatialFast
                        fillColor: card.palette.danger
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "close"
                        fill: 1
                        font.pixelSize: Tokens.iconLg
                        color: card.palette.fgOnPrimary
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Remove “%1”?").arg(card.cname)
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: card.palette.fg
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.preferredWidth: keepLabel.implicitWidth + Tokens.spacingLg * 2
                    Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                    radius: height / 2
                    color: keepMouse.containsMouse ? card.palette.plate : card.palette.section
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    StyledText { id: keepLabel; anchors.centerIn: parent; text: Translation.tr("Keep"); variant: "label"; font.weight: Font.DemiBold; color: card.palette.fg }
                    MouseArea {
                        id: keepMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.armed = false
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Keep")
                        Accessible.onPressAction: card.armed = false
                    }
                }
                Rectangle {
                    Layout.preferredWidth: removeLabel.implicitWidth + Tokens.spacingLg * 2
                    Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                    radius: height / 2
                    color: card.palette.danger
                    opacity: removeMouse.containsMouse ? 1 : 0.88
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    StyledText { id: removeLabel; anchors.centerIn: parent; text: Translation.tr("Remove"); variant: "label"; font.weight: Font.DemiBold; color: card.palette.fgOnPrimary }
                    MouseArea {
                        id: removeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { card.armed = false; ColorScheme.deleteScheme(card.cname) }
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Remove")
                        Accessible.onPressAction: ColorScheme.deleteScheme(card.cname)
                    }
                }
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (!hovered) card.armed = false
    }
    // Under the capsule and the layer (z: -1 puts it behind every button above), over the whole card: a left
    // press loads it into the editor, a right press asks which workspaces wear it.
    MouseArea {
        id: tap
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: !card.renaming
        onClicked: function (m) {
            if (m.button === Qt.RightButton) ColorScheme.choose(card.cname)
            else ColorScheme.useScheme(card.scheme)
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: card.cname
    Accessible.onPressAction: ColorScheme.useScheme(card.scheme)
}
