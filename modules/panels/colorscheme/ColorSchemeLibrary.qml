pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── ColorSchemeLibrary ── part of ColorSchemePanel.qml; `panel` is the ColorSchemePanel it belongs to. ──
ColumnLayout {
    id: libraryPane
    required property var panel
    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: panel.view === "library" && !panel.showProgress && !panel.picking
    spacing: Tokens.spacingSm

    // The pane rises and fades in as the other tabs do, and each card springs in on its own
    // inside it (PopIn).
    ViewEnter { target: libraryPane; active: libraryPane.visible }


    // ── Workspaces with a scheme of their own ───────────────────────
    // They outrank the shell's palette, so while any exist an Apply or a wallpaper change leaves them
    // as they are. Said here, with the way out, instead of leaving "it doesn't switch" to be worked out.
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.rightMargin: panel.contentPad
        visible: ColorScheme.perWorkspace
        implicitHeight: ownRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).alpha(panel.accent, 0.10)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(panel.accent, 0.28)
        RowLayout {
            id: ownRow
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd
            MaterialIcon { name: "tab"; color: panel.accent; font.pixelSize: Tokens.iconSm }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: ColorScheme.marked.length + (ColorScheme.marked.length === 1 ? " workspace wears" : " workspaces wear")
                      + " a scheme of its own (" + ColorScheme.marked.join(", ") + ") and ignores what you apply to the rest."
                variant: "caption"; wrapMode: Text.WordWrap
            }
            PanelButton {
                variant: "ghost"
                accent: panel.accent
                symbol: "close"
                label: Translation.tr("Clear")
                onActivated: ColorScheme.forgetAllWorkspaces()
            }
        }
    }

    // ── Search and sort ─────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.rightMargin: panel.contentPad
        visible: ColorScheme.presets.length >= panel.libToolsFrom
        spacing: Tokens.spacingSm


        InputField {
            Layout.fillWidth: true
            implicitHeight: Tokens.iconXl + Tokens.spacingMd
            cornerRadius: implicitHeight / 2
            icon: "search"
            placeholder: Translation.tr("Search schemes…")
            onEdited: function (v) { panel.libQuery = v }
            onKeyPressed: function (e) {
                if (e.key !== Qt.Key_Escape || panel.libQuery === "") return
                clear()
                e.accepted = true
            }
        }
        ChipTray {
            ChipButton {
                symbol: "bookmark"
                on:     panel.libStarOnly
                tint:   panel.accent
                onActivated: panel.libStarOnly = !panel.libStarOnly
            }
        }
        ChipTray {
            ChipButton {
                symbol: "text_fields"
                on:     panel.libSort === "name"
                tint:   panel.accent
                onActivated: panel.libSort = "name"
            }
            ChipButton {
                symbol: "schedule"
                on:     panel.libSort === "recent"
                tint:   panel.accent
                onActivated: panel.libSort = "recent"
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: ColorScheme.presets.length === 0
            ? emptyCol.implicitHeight + Tokens.spacingXxl * 2
            : panel.libMatches === 0
            ? noMatch.implicitHeight + Tokens.spacingXxl * 2
            : Math.min(chipFlow.implicitHeight, 360)

        Flickable {
            id: chipPane
            anchors.fill: parent
            contentHeight: chipFlow.implicitHeight
            clip: true

            Flow {
                id: chipFlow
                width: chipPane.width - panel.contentPad
                spacing: Tokens.spacingSm

                // A card that goes (searched out) or moves (a neighbour gone) glides to its place
                // instead of jumping — but only once the tab has settled. Delegates are built behind
                // a page that has no width yet, so on the first show EVERY card "moved" from the
                // corner into its place, on top of its own entrance: the pile-up that read as a low
                // frame rate.
                property bool glide: false
                Connections {
                    target: libraryPane
                    function onVisibleChanged() {
                        chipFlow.glide = false
                        if (libraryPane.visible) glideTimer.restart()
                    }
                }
                Timer { id: glideTimer; interval: Motion.emphasized + Motion.slow; onTriggered: chipFlow.glide = true }
                move: Transition {
                    enabled: chipFlow.glide
                    NumberAnimation { properties: "x,y"; duration: Motion.spatial; easing.type: Motion.travel }
                }

                Repeater {
                    model: panel.sortedPresets
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property string cname:  card.modelData.name
                        readonly property bool   loaded: ColorScheme.loadedName === card.cname
                        // The version for the shell's mode; a scheme with only the other one shows that,
                        // dimmed, so it is not mistaken for the real thing.
                        readonly property var    pick: Palette.pickVariant(card.modelData.variants, Config.themeMode)
                        readonly property var    shownPalette: card.pick.palette ?? card.modelData.palette
                        readonly property color  bg:  Palette.slotValue(card.shownPalette, "background")
                        readonly property color  ink: Palette.slotValue(card.shownPalette, "foreground")
                        readonly property bool   starred: Config.colorFavorites.indexOf(card.cname) >= 0
                        readonly property bool   matches: panel.presetMatches(card.cname)
                        // The workspaces wearing it (right-click → the picker).
                        readonly property var    wsList: ColorScheme.workspacesOf(card.cname)
                        property bool renaming: false

                        visible: card.matches
                        width: (chipFlow.width - Tokens.spacingSm) / 2
                        implicitHeight: cardCol.implicitHeight + Tokens.spacingMd * 2

                        function beginRename() {
                            card.renaming = true
                            renameField.setText(card.cname)
                            renameField.forceFocus()
                        }
                        function commitRename() {
                            const v = renameField.text.trim()
                            if (v !== "" && v !== card.cname) ColorScheme.renameScheme(card.cname, v)
                            card.renaming = false
                        }

                        // ── The entrance, and the lean ──────────────────────────
                        // Cards arrive on a spring a beat after their neighbours — every time the
                        // tab is shown (or a card is searched back in), not once when the delegates
                        // were built behind it (PopIn) — and lean toward the pointer / dip on a
                        // press, as the wallpaper tiles do.
                        PopIn { id: pop; active: libraryPane.visible && card.matches; index: card.index }

                        property real lean: cardTap.pressed ? 0.97 : cardHover.hovered ? 1.02 : 1.0
                        Behavior on lean { SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.002 } }
                        opacity: pop.opacity
                        scale:   card.lean * pop.scale

                        // ── Ring and inset, as the swatches ─────────────────────
                        property real inset: card.loaded ? Tokens.spacingXs : 0
                        Behavior on inset { SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.05 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radiusPill
                            color: "transparent"
                            border.width: Tokens.borderWidth * 2
                            border.color: panel.accent
                            opacity: card.loaded ? 1 : 0
                            scale:   card.loaded ? 1 : 0.95
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                        }

                        Rectangle {
                            id: cardFill
                            anchors.fill: parent
                            anchors.margins: Math.max(0, card.inset)
                            radius: Math.max(2, Tokens.radiusPill - card.inset)
                            color: card.bg
                            border.width: Tokens.borderWidth
                            border.color: Colors.of(QsWindow.window).alpha(card.ink, 0.14)

                            // How far the tray has pushed the content in from the right: the name and
                            // ribbon slide over on a spring as it arrives. A plain property carries the
                            // spring — a Behavior cannot sit on `anchors.*`.
                            property real gap: actions.shown ? actions.width + Tokens.spacingSm : 0
                            Behavior on gap { SpringAnimation { spring: 5.0; damping: 0.4; epsilon: 0.1 } }

                            // ── Name over its ribbon ───────────────────────────────
                            ColumnLayout {
                                id: cardCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin:  Tokens.spacingLg
                                anchors.rightMargin: Tokens.spacingLg + Math.max(0, cardFill.gap)
                                anchors.topMargin:   Tokens.spacingMd - card.inset
                                spacing: Tokens.spacingXs
                                opacity: card.renaming ? 0 : (card.pick.exact ? 1 : 0.6)
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    Layout.preferredHeight: Tokens.iconLg
                                    spacing: Tokens.spacingXs
                                    MaterialIcon {
                                        visible: card.loaded
                                        name: "check_circle_outline"; fill: 1
                                        color: card.ink; variant: "caption"
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.cname
                                        variant: "caption"
                                        font.weight: card.loaded ? Font.DemiBold : Font.Medium
                                        color: card.ink
                                        elide: Text.ElideRight
                                    }
                                    // Starred. A filled bookmark: the star's chunky points blur to a blob at this
                                    // size, a bookmark stays a clean solid shape.
                                    MaterialIcon {
                                        visible: card.starred
                                        name: "bookmark"; fill: 1
                                        color: card.ink; font.pixelSize: Tokens.iconSm
                                    }
                                    // The workspaces that wear it.
                                    MaterialIcon {
                                        visible: card.wsList.length > 0
                                        name: "workspaces"; fill: 1
                                        color: card.ink; font.pixelSize: Tokens.iconSm
                                    }
                                    StyledText {
                                        visible: card.wsList.length > 0
                                        text: card.wsList.join(" ")
                                        variant: "micro"
                                        font.weight: Font.DemiBold
                                        color: card.ink
                                    }
                                    // Which modes it holds: lit when it has that version, faint when not.
                                    MaterialIcon {
                                        name: "light_mode"; fill: 0
                                        opacity: card.modelData.variants.light ? 0.9 : 0.25
                                        color: card.ink; font.pixelSize: Tokens.iconSm
                                    }
                                    MaterialIcon {
                                        name: "dark_mode"; fill: 0
                                        opacity: card.modelData.variants.dark ? 0.9 : 0.25
                                        color: card.ink; font.pixelSize: Tokens.iconSm
                                    }
                                }

                                // The palette, as a ribbon. Cells placed by arithmetic, not a layout — the
                                // edges rounded to whole pixels, so no hairline seams between them either.
                                Item {
                                    id: rib
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    Layout.preferredHeight: Tokens.iconSm

                                    Repeater {
                                        model: 15
                                        delegate: Rectangle {
                                            required property int index
                                            x:      Math.round(index * rib.width / 15)
                                            width:  Math.round((index + 1) * rib.width / 15) - x
                                            height: rib.height
                                            topLeftRadius:     index === 0  ? height / 2 : 0
                                            bottomLeftRadius:  index === 0  ? height / 2 : 0
                                            topRightRadius:    index === 14 ? height / 2 : 0
                                            bottomRightRadius: index === 14 ? height / 2 : 0
                                            color: Palette.slotValue(card.shownPalette, "color" + (index + 1))
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: height / 2
                                        color: "transparent"
                                        border.width: Tokens.borderWidth
                                        border.color: Colors.of(QsWindow.window).alpha(card.ink, 0.18)
                                    }
                                }
                            }

                            // ── Rename in place ──────────────────────────────────────
                            InputField {
                                id: renameField
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin:  Tokens.spacingMd
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

                            // ── Edit / delete, over the right edge ───────────────────
                            Item {
                                id: actions
                                anchors.right: parent.right
                                anchors.rightMargin: Tokens.spacingSm
                                anchors.verticalCenter: parent.verticalCenter
                                width:  tray.implicitWidth
                                height: tray.implicitHeight
                                transformOrigin: Item.Right
                                readonly property bool shown: (cardHover.hovered || delLatch.armed) && !card.renaming
                                property real pop: actions.shown ? 1 : 0
                                Behavior on pop { SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.005 } }
                                opacity: Math.min(1, actions.pop * 1.5)
                                scale:   0.7 + 0.3 * actions.pop
                                visible: actions.opacity > 0.01

                                HoverHandler { id: actionsHover }

                                ArmLatch {
                                    id: delLatch
                                    onConfirmed: ColorScheme.deleteScheme(card.cname)
                                }

                                ChipTray {
                                    id: tray
                                    ChipButton {
                                        symbol: "bookmark"
                                        on:     card.starred
                                        tint:   panel.accent
                                        onActivated: Config.colorFavToggle(card.cname)
                                    }
                                    ChipButton {
                                        symbol: "edit"
                                        tint:   panel.accent
                                        onActivated: card.beginRename()
                                    }
                                    ChipButton {
                                        symbol: "delete"
                                        label:  delLatch.armed ? "Delete?" : ""
                                        on:     delLatch.armed
                                        tint:   Colors.of(QsWindow.window).danger
                                        onActivated: delLatch.trigger()
                                    }
                                }
                            }
                        }

                        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                        // Not under the tray: a tap on edit / delete is theirs, and TapHandlers
                        // do not stop one another.
                        TapHandler {
                            id: cardTap
                            onTapped: if (!actionsHover.hovered && !card.renaming)
                                          ColorScheme.useScheme(card.modelData)
                        }
                        // Right-click: which workspaces wear it.
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: if (!actionsHover.hovered && !card.renaming)
                                          ColorScheme.choose(card.cname)
                        }
                    }
                }
            }
        }
        Scrollbar { flickable: chipPane }

        // Nothing saved yet.
        ColumnLayout {
            id: emptyCol
            anchors.centerIn: parent
            visible: ColorScheme.presets.length === 0 && !ColorScheme.listing
            spacing: Tokens.spacingSm

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                name: "bookmarks"
                fill: 0
                font.pixelSize: Tokens.iconXl + Tokens.spacingXl
                color: Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No saved schemes yet")
                variant: "body"; emphasis: "dim"
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Build a palette in the editor and hit Save.")
                variant: "caption"; emphasis: "dim"
            }
        }

        // Saved schemes, but none that the search leaves.
        ColumnLayout {
            id: noMatch
            anchors.centerIn: parent
            visible: ColorScheme.presets.length > 0 && panel.libMatches === 0
            spacing: Tokens.spacingSm

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                name: "search"
                fill: 0
                font.pixelSize: Tokens.iconXl + Tokens.spacingXl
                color: Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: panel.libQuery.trim() === "" && panel.libStarOnly
                      ? "No starred schemes yet"
                      : "No scheme matches “" + panel.libQuery.trim() + "”"
                variant: "body"; emphasis: "dim"
            }
        }
    }
}
