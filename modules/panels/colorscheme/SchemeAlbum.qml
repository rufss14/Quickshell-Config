pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── SchemeAlbum ───────────────────────────────────────────────────────────────
// The colour scheme page's Album view: let the cover of what is playing paint the shell. Set it up first, then
// switch it on: everything here works while following is off, and the cover's colours are read for a PREVIEW
// (`AlbumScheme.previewWanted`) so the choices have something to be judged against. The loud card on the left
// wears the cover's palette while this view is open.
//
// One scroll of plates:
//   the cover plate   the cover on a canvas, the track, where it plays, what the album is doing in words, and the
//                     eight colours it gives as tiles. Loud (accent container) while the album drives the shell.
//   the actions       Follow (the page's one loud pill), then what you can do with the colours before or while:
//                     Peek (hold to wear them on the whole shell), Keep (save them as a preset), Edit (open them in
//                     the Palette view).
//   While it plays    the lock (the cover beats pinned colours and applied schemes) and how long it stays after
//                     the music stops. First, because it is what people look for.
//   Where             everywhere, a chosen set of workspaces, or the workspace Spotify is on.
//   Applies to        this shell only (held in memory) or everything (the system-wide colour files).
//
// Each choice of place says what it means in one line under its group, replaced and not rewritten when the choice
// changes (SwapFade). A scope narrower than everywhere is in memory only and is placed by WorkspaceTheme, so
// "Applies to" is not the user's to choose then.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool following: Config.albumScheme
    readonly property string scope: AlbumScheme.scoped ? Config.albumScope : "all"
    readonly property bool live: AlbumScheme.active
    readonly property var cover: AlbumScheme.coverPalette
    readonly property bool hasCover: root.cover !== null && root.cover !== undefined
    readonly property var player: AlbumScheme.player
    readonly property string track: root.player?.trackTitle ?? ""

    visible: root.panel.view === "album" && !root.panel.showProgress && !root.panel.picking

    ViewEnter { target: root; active: root.visible }
    // Reading the cover for a preview is only done while this view is open.
    Binding { target: AlbumScheme; property: "previewWanted"; value: root.visible }

    // What the plate says under the track, in words.
    readonly property string status: root.following ? AlbumScheme.reasonText
        : !root.player ? Translation.tr("Nothing is playing. Play something to see its colours.")
        : !AlbumScheme.eligible ? Translation.tr("This source does not give reliable cover art, so its colours are ignored.")
        : AlbumScheme.artUrl === "" ? Translation.tr("This track has no cover art.")
        : root.hasCover ? Translation.tr("This is what the cover gives. Switch it on to wear it.")
        : Translation.tr("Reading the cover…")

    // What the choice of place means.
    readonly property string whereNote: root.scope === "workspaces"
        ? Translation.tr("Only what is on those workspaces wears it. GTK and Qt apps and browsers read one system-wide palette, so they cannot follow a single workspace.")
        : root.scope === "spotify"
        ? (WorkspaceTheme.spotifyWorkspace > 0
           ? Translation.tr("Spotify is on workspace %1, and the cover follows its window if it moves. The other workspaces keep their colours.").arg(WorkspaceTheme.spotifyWorkspace)
           : Translation.tr("Spotify is not open, so nothing wears the cover yet. It lands on whichever workspace its window is on."))
        : Translation.tr("The bar, the panels and every window wear the cover.")
    readonly property string reachNote: AlbumScheme.scoped
        ? Translation.tr("A single workspace cannot own the system-wide colour files, so this stays on the shell.")
        : Config.albumSchemeSystem
        ? Translation.tr("Also the terminal, GTK and Qt apps, Discord and the rest. They repaint on every track, and switching off rebuilds the wallpaper's palette.")
        : Translation.tr("The bar, the panels and the overview, held in memory. A track change is a repaint, and switching off gives the wallpaper's palette back at once.")
    property string shownWhere: ""
    property string shownReach: ""
    Component.onCompleted: { root.shownWhere = root.whereNote; root.shownReach = root.reachNote }
    SwapFade { target: whereNote; key: root.whereNote; shownKey: root.shownWhere; onSwapped: root.shownWhere = root.whereNote }
    SwapFade { target: reachNote; key: root.reachNote; shownKey: root.shownReach; onSwapped: root.shownReach = root.reachNote }

    // The cover's palette as the editor takes it (no bookkeeping keys).
    function plain() { return root.hasCover ? { special: root.cover.special, colors: root.cover.colors } : null }
    property bool kept: false
    Timer { id: keptTimer; interval: 1500; onTriggered: root.kept = false }

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

            // ══ The cover plate ═══════════════════════════════════════════════════
            Rectangle {
                id: plate
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 4 + Tokens.spacingMd
                readonly property color ink: root.live ? root.palette.fgOnPrimaryContainer : root.palette.fg
                readonly property color inkDim: root.live ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
                radius: Tokens.radiusXl
                color: root.live ? root.palette.primaryContainer : root.palette.section
                Behavior on color { ColorAnimation { duration: Motion.standard } }

                // The cover, on a canvas, its corner going rounder while it is worn.
                ClippingRectangle {
                    id: coverBox
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - Tokens.spacingLg * 2
                    height: width
                    radius: root.live ? Tokens.radiusXl : Tokens.radiusCard
                    Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    color: root.palette.plate
                    border.width: Tokens.borderWidth
                    border.color: root.palette.alpha(root.palette.fg, 0.12)

                    Image {
                        id: art
                        anchors.fill: parent
                        source: AlbumScheme.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    }
                    MorphShape {
                        anchors.centerIn: parent
                        width: parent.width * 0.62
                        height: width
                        shape: "cookie9"
                        fillColor: root.palette.section
                        opacity: art.status === Image.Ready ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "music_note"
                        fill: 1
                        font.pixelSize: Tokens.iconXl
                        color: root.palette.fgMuted
                        opacity: art.status === Image.Ready ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    }
                }

                ColumnLayout {
                    anchors.left: coverBox.right
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingLg
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacingXs

                    StyledText {
                        Layout.fillWidth: true
                        text: (root.live ? Translation.tr("Wearing the cover")
                             : root.hasCover ? Translation.tr("Preview") : Translation.tr("Album colours")).toUpperCase()
                        variant: "caption"
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: plate.inkDim
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.track || Translation.tr("Nothing playing")
                        variant: "headline"
                        font.weight: Font.DemiBold
                        color: plate.ink
                        elide: Text.ElideRight
                    }
                    // The artist, and which player it comes from.
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: [root.player?.trackArtist ?? "", root.player?.identity ?? ""].filter(x => x !== "").join("  ·  ")
                        variant: "caption"
                        font.weight: Font.Medium
                        color: plate.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.status
                        variant: "caption"
                        color: plate.inkDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    // The eight colours it gives, as tiles that arrive one after another.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.topMargin: Tokens.spacingXs
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: 8
                            delegate: Rectangle {
                                id: tile
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.iconLg
                                radius: Tokens.radiusSm
                                color: root.hasCover ? Palette.slotValue(root.cover, "color" + (tile.index + 1))
                                                     : root.palette.alpha(plate.ink, 0.12)
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                PopIn { id: pop; active: root.visible; index: tile.index; cap: 8 }
                                opacity: pop.opacity
                                scale: pop.scale
                            }
                        }
                    }
                }
            }

            // ══ The actions ═══════════════════════════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                // Follow: the page's one loud pill. Off it invites; on it is the accent, with a tick.
                Rectangle {
                    id: follow
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                    radius: height / 2
                    color: root.following ? root.palette.primary : root.palette.primaryContainer
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    readonly property color fg: root.following ? root.palette.fgOnPrimary : root.palette.fgOnPrimaryContainer
                    SpringValue {
                        id: followLean
                        target: followTap.pressed ? 0.97 : followHover.hovered ? 1.02 : 1
                        spec: Motion.springSpatialFast
                        epsilon: 0.001
                    }
                    scale: followLean.value
                    StateLayer {
                        anchors.fill: parent
                        radius: follow.radius
                        hovered: followHover.hovered
                        layerColor: follow.fg
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: Tokens.spacingMd
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Tokens.iconXl - Tokens.spacingXs
                            height: width
                            MorphShape {
                                anchors.fill: parent
                                shape: root.following ? "cookie9" : "circle"
                                spec: Motion.springSpatialFast
                                fillColor: root.palette.alpha(follow.fg, root.following ? 0.28 : 0.16)
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: root.following ? "check" : "music_note"
                                fill: 1
                                font.pixelSize: Tokens.iconMd
                                color: follow.fg
                            }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.following ? Translation.tr("Following the cover") : Translation.tr("Follow the cover")
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: follow.fg
                        }
                    }
                    HoverHandler { id: followHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: followTap; onTapped: Config.albumScheme = !Config.albumScheme }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: Translation.tr("Follow the album cover")
                    Accessible.checkable: true
                    Accessible.checked: root.following
                    Accessible.onPressAction: Config.albumScheme = !Config.albumScheme
                }

                // Hold to wear the cover's colours on the whole shell; let go and they are gone.
                ChipButton {
                    visible: root.hasCover && !root.live
                    tonal: true
                    symbol: "visibility"
                    label: Translation.tr("Peek")
                    on: ColorScheme.peeking
                    tint: root.panel.accent
                    enabled: !ColorScheme.busy
                    onPressedChanged: if (pressed) ColorScheme.peek(root.plain()); else ColorScheme.endPeek()
                    HoverTip { text: Translation.tr("Hold to see the cover's colours on the whole shell"); below: true }
                }
                // Keep the colours as a preset of their own, named after the track.
                ChipButton {
                    visible: root.hasCover
                    tonal: true
                    symbol: root.kept ? "check" : "bookmark"
                    on: root.kept
                    tint: root.panel.accent
                    enabled: root.track !== ""
                    onActivated: {
                        const v = ({})
                        v[Config.themeMode === "light" ? "light" : "dark"] = root.plain()
                        ColorScheme.saveScheme(root.track, v)
                        root.kept = true
                        keptTimer.restart()
                    }
                    HoverTip { text: root.kept ? Translation.tr("Saved to Presets") : Translation.tr("Keep these colours as a preset"); below: true }
                }
                // Open them in the Palette view to change them.
                ChipButton {
                    visible: root.hasCover
                    tonal: true
                    symbol: "edit"
                    tint: root.panel.accent
                    onActivated: ColorScheme.openPalette(root.track, root.plain())
                    HoverTip { text: Translation.tr("Edit these colours"); below: true; alignEnd: true }
                }
            }

            // ══ While it plays ════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    text: Translation.tr("While it plays").toUpperCase()
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    color: root.palette.fgMuted
                }
                OptionCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                    symbol: Config.albumSchemeLock ? "lock" : "lock_open"
                    shape: "cookie6"
                    label: Translation.tr("Lock the cover in")
                    detail: Translation.tr("It beats pinned colours and applied schemes until playback stops")
                    on: Config.albumSchemeLock
                    onActivated: Config.albumSchemeLock = !Config.albumSchemeLock
                }

                // How long it stays once the music stops.
                StyledText {
                    Layout.topMargin: Tokens.spacingXs
                    text: Translation.tr("After it stops")
                    variant: "caption"
                    emphasis: "dim"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    uniformCellSizes: true
                    Repeater {
                        model: [
                            { v: 5,   label: Translation.tr("5 seconds"),  detail: "",                                shape: "squircle" },
                            { v: 20,  label: Translation.tr("20 seconds"), detail: Translation.tr("Default"),        shape: "cookie9"  },
                            { v: 120, label: Translation.tr("2 minutes"),  detail: "",                                shape: "clover"   },
                            { v: -1,  label: Translation.tr("Stay"),       detail: Translation.tr("Until replaced"), shape: "sunny"    }
                        ]
                        delegate: OptionCard {
                            id: hold
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                            symbol: "schedule"
                            shape: hold.modelData.shape
                            label: hold.modelData.label
                            detail: hold.modelData.detail
                            on: Config.albumHold === hold.modelData.v
                            onActivated: Config.albumHold = hold.modelData.v
                        }
                    }
                }
            }

            // ══ Where ═════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    text: Translation.tr("Where").toUpperCase()
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    color: root.palette.fgMuted
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    uniformCellSizes: true
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                        symbol: "public"
                        shape: "cookie9"
                        label: Translation.tr("Everywhere")
                        detail: Translation.tr("The whole shell")
                        on: root.scope === "all"
                        onActivated: Config.albumScope = "all"
                    }
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                        symbol: "workspaces"
                        shape: "clover"
                        label: Translation.tr("Workspaces")
                        detail: Config.albumWorkspaces.length > 0 ? Config.albumWorkspaces.join(", ") : Translation.tr("Pick some")
                        on: root.scope === "workspaces"
                        onActivated: {
                            Config.albumScope = "workspaces"
                            // Nothing chosen yet: ask straight away.
                            if (Config.albumWorkspaces.length === 0) root.panel.pickingAlbum = true
                        }
                    }
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                        symbol: "album"
                        shape: "sunny"
                        label: Translation.tr("Spotify's")
                        detail: Translation.tr("Where it plays")
                        on: root.scope === "spotify"
                        onActivated: Config.albumScope = "spotify"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    StyledText {
                        id: whereNote
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: root.shownWhere
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    ChipButton {
                        visible: root.scope === "workspaces"
                        tonal: true
                        symbol: "workspaces"
                        label: Config.albumWorkspaces.length > 0 ? Translation.tr("Change") : Translation.tr("Choose")
                        tint: root.panel.accent
                        onActivated: root.panel.pickingAlbum = true
                    }
                }
            }

            // ══ Applies to ════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    text: Translation.tr("Applies to").toUpperCase()
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    color: root.palette.fgMuted
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    uniformCellSizes: true
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                        enabled: !AlbumScheme.scoped
                        symbol: "dashboard"
                        shape: "squircle"
                        label: Translation.tr("This shell")
                        detail: Translation.tr("Held in memory")
                        on: !(Config.albumSchemeSystem && !AlbumScheme.scoped)
                        onActivated: Config.albumSchemeSystem = false
                    }
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                        enabled: !AlbumScheme.scoped
                        symbol: "layers"
                        shape: "hexagon"
                        label: Translation.tr("Everything")
                        detail: Translation.tr("Apps too")
                        on: Config.albumSchemeSystem && !AlbumScheme.scoped
                        onActivated: Config.albumSchemeSystem = true
                    }
                }
                StyledText {
                    id: reachNote
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: root.shownReach
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

        }
    }
    Scrollbar { flickable: pane }
}
