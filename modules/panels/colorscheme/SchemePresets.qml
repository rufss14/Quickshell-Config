pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── SchemePresets ─────────────────────────────────────────────────────────────
// The colour scheme page's Presets view: every palette you can put on, as cards that are miniatures of what
// they wear (SchemeCard). Three groups, each under its own heading: the wallpaper's own colours (what the shell
// wears when nothing is held), the ones you saved, and the classics the shell ships. A search field that types
// its own hints and counts what it found, a bookmark filter and a sort (name or most recent) appear once there
// are enough to need them. A card the pointer is on opens its tools.
//
// The wallpaper's colours are a hero of their own at the top: pressing its button lets go of whatever is held and
// takes the wallpaper's colours again. "Yours" and "Classics" fold away under their headings.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    spacing: Tokens.spacingMd
    visible: root.panel.view === "library" && !root.panel.showProgress && !root.panel.picking

    ViewEnter { target: root; active: root.visible }

    // ── Workspaces with a scheme of their own ───────────────────────────────
    // They outrank the shell's palette, so while any exist an Apply or a wallpaper change leaves them as they
    // are. Said here, with the way out, instead of leaving "it does not switch" to be worked out.
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: ColorScheme.perWorkspace
        implicitHeight: ownRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: root.palette.primaryContainer
        RowLayout {
            id: ownRow
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingMd
            anchors.topMargin: Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd
            MaterialIcon { name: "workspaces"; fill: 1; color: root.palette.fgOnPrimaryContainer; font.pixelSize: Tokens.iconLg }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: ColorScheme.marked.length === 1
                    ? Translation.tr("Workspace %1 wears a scheme of its own and ignores what you apply to the rest.").arg(ColorScheme.marked.join(", "))
                    : Translation.tr("Workspaces %1 wear a scheme of their own and ignore what you apply to the rest.").arg(ColorScheme.marked.join(", "))
                variant: "caption"
                color: root.palette.fgOnPrimaryContainer
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            ChipButton {
                tonal: true
                symbol: "close"
                label: Translation.tr("Clear")
                tint: root.panel.accent
                onActivated: ColorScheme.forgetAllWorkspaces()
            }
        }
    }

    // ── Search, bookmarks, sort ─────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.panel.mySchemes.length + root.panel.classicSchemes.length >= root.panel.libToolsFrom
        spacing: Tokens.spacingMd

        SearchPill {
            Layout.fillWidth: true
            lead: Translation.tr("Search schemes")
            accent: root.panel.accent
            found: root.panel.libMatches
            total: root.panel.mySchemes.length + root.panel.classicSchemes.length + 1
            hints: [{ key: "dark", text: Translation.tr("by name") },
                    { key: "light", text: Translation.tr("any word in it") }]
            onEdited: function (v) { root.panel.libQuery = v }
        }
        ChipButton {
            tonal: true
            symbol: "bookmark"
            on: root.panel.libStarOnly
            tint: root.panel.accent
            onActivated: root.panel.libStarOnly = !root.panel.libStarOnly
            HoverTip { text: root.panel.libStarOnly ? Translation.tr("Show all") : Translation.tr("Only bookmarked"); below: true }
        }
        ChipButton {
            tonal: true
            symbol: root.panel.libSort === "name" ? "text_fields" : "schedule"
            tint: root.panel.accent
            onActivated: root.panel.libSort = root.panel.libSort === "name" ? "recent" : "name"
            HoverTip {
                text: root.panel.libSort === "name" ? Translation.tr("Sorted by name. Press for the newest first")
                                                    : Translation.tr("Newest first. Press to sort by name")
                below: true
                alignEnd: true
            }
        }
    }

    // ── The cards ───────────────────────────────────────────────────────────
    Item {
        id: listArea
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
            id: pane
            anchors.fill: parent
            contentHeight: flow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: flow
                width: pane.width - Tokens.spacingLg
                spacing: Tokens.spacingMd

                // A card that goes (searched out) or moves (a neighbour gone) glides to its place instead of
                // jumping, but only once the page has settled: delegates are built behind a page that has no
                // width yet, and on the first show EVERY card "moved" from the corner into its place.
                property bool glide: false
                Connections {
                    target: root
                    function onVisibleChanged() {
                        flow.glide = false
                        if (root.visible) glideTimer.restart()
                    }
                }
                Timer { id: glideTimer; interval: Motion.emphasized + Motion.slow; onTriggered: flow.glide = true }
                move: Transition {
                    enabled: flow.glide
                    NumberAnimation { properties: "x,y"; duration: Motion.spatial; easing.type: Motion.travel }
                }

                readonly property real cardW: (flow.width - Tokens.spacingMd) / 2

                Component {
                    id: schemeCard
                    SchemeCard {
                        panel: root.panel
                        width: flow.cardW
                        group: "mine"
                    }
                }
                Component {
                    id: classicCard
                    SchemeCard {
                        panel: root.panel
                        width: flow.cardW
                        group: "classic"
                    }
                }

                // ── The wallpaper's own colours: a hero of its own ──────────────
                // What the shell wears when nothing is held. The picture on screen on a canvas, what it is doing
                // in words, the eight colours it gives, and the one button. In use, the card goes loud and round.
                Rectangle {
                    id: wall
                    readonly property bool on: ColorScheme.wearingWallpaper
                    readonly property color ink: wall.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
                    readonly property color inkDim: root.palette.alpha(wall.ink, 0.72)
                    readonly property string pic: Wallpaper.sharedPicture !== "" ? "file://" + Wallpaper.sharedPicture : ""
                    visible: root.panel.libWallShown
                    width: flow.width
                    implicitHeight: Tokens.iconXl * 4
                    radius: Tokens.radiusXl
                    color: wall.on ? root.palette.primaryContainer : root.palette.section
                    Behavior on color { ColorAnimation { duration: Motion.standard } }

                    // The picture, on a canvas, at the screen's own shape.
                    ClippingRectangle {
                        id: shot
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spacingLg
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height - Tokens.spacingLg * 2
                        width: Math.round(height * 16 / 9)
                        radius: Tokens.radiusCard
                        color: root.palette.plate
                        border.width: Tokens.borderWidth
                        border.color: root.palette.alpha(root.palette.fg, 0.12)
                        Image {
                            anchors.fill: parent
                            source: wall.pic
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 360
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "wallpaper"
                            font.pixelSize: Tokens.iconXl
                            color: root.palette.fgMuted
                            visible: wall.pic === ""
                        }
                    }

                    ColumnLayout {
                        anchors.left: shot.right
                        anchors.leftMargin: Tokens.spacingLg
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.spacingLg
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingXs

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("From the wallpaper").toUpperCase()
                            variant: "caption"
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                            color: wall.inkDim
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Follow the wallpaper")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: wall.ink
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: wall.on ? Translation.tr("In use: every new wallpaper repaints the shell")
                                          : Translation.tr("Let go of the scheme and take the wallpaper's colours")
                            variant: "caption"
                            color: wall.inkDim
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.topMargin: Tokens.spacingXs
                            spacing: Tokens.spacingMd
                            // The colours it gives, as discs that arrive one after another.
                            Row {
                                spacing: -Tokens.spacingXs
                                Repeater {
                                    model: 8
                                    delegate: Rectangle {
                                        id: dot
                                        required property int index
                                        width: Tokens.iconMd + Tokens.spacingXs
                                        height: width
                                        radius: width / 2
                                        color: root.palette.ansi(dot.index + 1)
                                        border.width: Tokens.borderWidth * 2
                                        border.color: wall.color
                                        PopIn { id: dotPop; active: root.visible; index: dot.index; cap: 8 }
                                        scale: dotPop.scale
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            // The one button: a filled pill that says what it does, then that it is done.
                            Rectangle {
                                id: wallBtn
                                implicitWidth: wallRow.implicitWidth + Tokens.spacingLg * 2
                                implicitHeight: Tokens.iconXl + Tokens.spacingXs
                                radius: height / 2
                                color: wall.on ? root.palette.primary : root.palette.primaryContainer
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                opacity: ColorScheme.busy && !wall.on ? 0.45 : 1
                                readonly property color fg: wall.on ? root.palette.fgOnPrimary : root.palette.fgOnPrimaryContainer
                                SpringValue {
                                    id: wallLean
                                    target: wallTap.pressed ? 0.95 : wallHover.hovered && !wall.on ? 1.04 : 1
                                    spec: Motion.springSpatialFast
                                    epsilon: 0.001
                                }
                                scale: wallLean.value
                                Row {
                                    id: wallRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.spacingSm
                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: wall.on ? "check" : "wallpaper"
                                        fill: 1
                                        font.pixelSize: Tokens.iconMd
                                        color: wallBtn.fg
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: wall.on ? Translation.tr("In use") : Translation.tr("Use these colours")
                                        variant: "label"
                                        font.weight: Font.DemiBold
                                        color: wallBtn.fg
                                    }
                                }
                                HoverHandler { id: wallHover; cursorShape: wall.on ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                TapHandler { id: wallTap; onTapped: if (!wall.on && !ColorScheme.busy) ColorScheme.useWallpaper() }
                                Accessible.role: Accessible.Button
                                Accessible.name: Translation.tr("Follow the wallpaper")
                                Accessible.onPressAction: if (!wall.on && !ColorScheme.busy) ColorScheme.useWallpaper()
                            }
                        }
                    }
                }

                // ── Saved by you ───────────────────────────────────────────────
                GroupHeader {
                    width: flow.width
                    visible: root.panel.libMatchesMine > 0
                    symbol: "bookmarks"
                    title: Translation.tr("Yours")
                    count: root.panel.libMatchesMine
                    foldable: true
                    folded: root.panel.isFolded("mine") && root.panel.libQuery.trim() === ""
                    onToggled: root.panel.fold("mine")
                }
                Repeater { model: root.panel.mySchemes; delegate: schemeCard }

                // ── Shipped with the shell ─────────────────────────────────────
                GroupHeader {
                    width: flow.width
                    visible: root.panel.libMatchesClassic > 0
                    symbol: "auto_awesome"
                    title: Translation.tr("Classics")
                    count: root.panel.libMatchesClassic
                    foldable: true
                    folded: root.panel.isFolded("classic") && root.panel.libQuery.trim() === ""
                    onToggled: root.panel.fold("classic")
                }
                Repeater { model: root.panel.classicSchemes; delegate: classicCard }
            }
        }
        Scrollbar { flickable: pane }

        // Schemes, but none that the search leaves.
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.panel.libMatches === 0
            spacing: Tokens.spacingSm
            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                name: "search"
                fill: 0
                font.pixelSize: Tokens.iconXl + Tokens.spacingXl
                color: root.palette.fgDim
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.panel.libQuery.trim() === "" && root.panel.libStarOnly
                    ? Translation.tr("Nothing bookmarked yet")
                    : Translation.tr("No scheme matches “%1”").arg(root.panel.libQuery.trim())
                variant: "body"
                emphasis: "dim"
            }
        }
    }
}
