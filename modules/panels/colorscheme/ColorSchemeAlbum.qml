pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── ColorSchemeAlbum ── part of ColorSchemePanel.qml; `panel` is the ColorSchemePanel it belongs to. ──
ColumnLayout {
    Layout.fillHeight: false
    id: albumPane
    required property var panel
    Layout.fillWidth: true
    Layout.rightMargin: panel.contentPad
    visible: panel.view === "album" && !panel.showProgress && !panel.picking
    spacing: Tokens.spacingXs

    ViewEnter { target: albumPane; active: albumPane.visible }

    SettingRow {
        label: Translation.tr("Follow album cover")
        detail: Translation.tr("Wears the colours of whatever's playing — everywhere, or only on some ")
              + "workspaces — and hands them back when the music stops."
        wrapDetail: true
        Toggle {
            checked: Config.albumScheme
            onToggled: Config.albumScheme = !Config.albumScheme
        }
    }

    Divider {}

    // ── Where ──────────────────────────────────────────────────────
    // The whole shell, a chosen set of workspaces, or the one Spotify is on. A scope narrower
    // than everywhere is in-memory only (see Reach below) and is placed by WorkspaceTheme: the
    // shell on the screen showing that workspace, and the windows, terminals, Discord and
    // Spotify that are on it — whether or not you are looking.
    ColumnLayout {
        id: whereCol
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        spacing: Tokens.spacingXs
        opacity: Config.albumScheme ? 1.0 : 0.4

        readonly property string scope: AlbumScheme.scoped ? Config.albumScope : "all"
        readonly property string note: whereCol.scope === "workspaces"
            ? "Only what is on those workspaces wears it: the bar and panels on the screen showing one, "
            + "and the windows, terminals, Discord and Spotify on it. GTK/Qt apps and browsers read one "
            + "system-wide palette, so they can't follow a single workspace."
            : whereCol.scope === "spotify"
            ? (WorkspaceTheme.spotifyWorkspace > 0
               ? "Spotify is on workspace " + WorkspaceTheme.spotifyWorkspace + " — it follows the window "
                 + "if it moves. Everything on that workspace wears the cover; the rest keep their colours."
               : "Spotify isn't open, so nothing wears the cover yet. It lands on whichever workspace "
                 + "Spotify's window is on.")
            : ""

        StyledText { text: "Where"; variant: "caption"; emphasis: "dim" }

        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            enabled: Config.albumScheme
            accent: panel.accent
            model: [
                { value: "all",        label: "Everywhere" },
                { value: "workspaces", label: "Chosen workspaces" },
                { value: "spotify",    label: "Spotify's workspace" }
            ]
            current: whereCol.scope
            onPicked: function (v) {
                Config.albumScope = v
                // Nothing chosen yet: ask straight away.
                if (v === "workspaces" && Config.albumWorkspaces.length === 0) panel.pickingAlbum = true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: whereCol.scope === "workspaces"
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: Config.albumWorkspaces.length > 0
                      ? "Workspaces " + Config.albumWorkspaces.join(", ")
                      : "No workspaces chosen"
                variant: "caption"
                elide: Text.ElideRight
            }
            PanelButton {
                variant: "normal"
                enabled: Config.albumScheme
                label: Config.albumWorkspaces.length > 0 ? "Change" : "Choose"
                onActivated: panel.pickingAlbum = true
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: whereCol.note !== ""
            wrapMode: Text.WordWrap
            variant: "micro"; emphasis: "dim"
            text: whereCol.note
        }
    }

    Divider {}

    // ── Reach ──────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillHeight: false
        id: reachCol
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        spacing: Tokens.spacingXs
        opacity: Config.albumScheme && !AlbumScheme.scoped ? 1.0 : 0.4

        // What the choice means. When it changes the line is REPLACED (SwapFade, which
        // wants its own held copy of the text).
        readonly property string note: AlbumScheme.scoped
            ? "Not for a single workspace — “Everything” writes the system-wide colour files, "
            + "which no one workspace can own."
            : Config.albumSchemeSystem
            ? "Bar, panels, overview — plus the terminal, GTK/Qt apps, Discord and "
            + "the rest. Repaints them all on every track; turning it off "
            + "regenerates the wallpaper's palette."
            : "Bar, panels and overview only, held in memory. A track change is "
            + "just a repaint, and switching off restores the wallpaper's palette "
            + "instantly."
        property string shownNote: ""
        Component.onCompleted: reachCol.shownNote = reachCol.note
        SwapFade {
            target:   reachNoteText
            key:      reachCol.note
            shownKey: reachCol.shownNote
            onSwapped: reachCol.shownNote = reachCol.note
        }

        StyledText { text: "Applies to"; variant: "caption"; emphasis: "dim" }

        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            // The column above dims to 40% while following is off; this is what stops it taking clicks.
            enabled: Config.albumScheme && !AlbumScheme.scoped
            accent: panel.accent
            model: [
                { value: "shell",  label: "This shell" },
                { value: "system", label: "Everything" }
            ]
            current: Config.albumSchemeSystem && !AlbumScheme.scoped ? "system" : "shell"
            onPicked: function (v) { Config.albumSchemeSystem = (v === "system") }
        }

        StyledText {
            id: reachNoteText
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            wrapMode: Text.WordWrap
            variant: "micro"; emphasis: "dim"
            text: reachCol.shownNote
        }
    }

    Divider {}

    SettingRow {
        label: Translation.tr("Lock while playing")
        detail: Translation.tr("Album colours win over pinned colours and applied schemes until ")
              + "playback stops — nothing overwrites them."
        wrapDetail: true
        opacity: Config.albumScheme ? 1.0 : 0.4
        Toggle {
            checked: Config.albumSchemeLock
            enabled: Config.albumScheme
            onToggled: Config.albumSchemeLock = !Config.albumSchemeLock
        }
    }

    // ── Status ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        implicitHeight: statusCol.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: statusCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillHeight: false
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                // The note in a disc that lights while the album is driving the shell.
                Rectangle {
                    Layout.preferredWidth:  Tokens.iconXl + Tokens.spacingXs
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXs
                    radius: height / 2
                    color: AlbumScheme.active ? panel.accent
                                              : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "music_note"
                        fill: AlbumScheme.active ? 1 : 0
                        color: AlbumScheme.active ? Colors.of(QsWindow.window).fgOnPrimary
                                                  : Colors.of(QsWindow.window).fgDim
                        variant: "caption"
                        Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                        Behavior on color { ColorAnimation  { duration: Motion.standard } }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: AlbumScheme.reasonText
                    variant: "caption"; emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
                MaterialIcon {
                    visible: AlbumScheme.active && AlbumScheme.locked
                    name: "lock"; fill: 1
                    color: Colors.of(QsWindow.window).primary; variant: "caption"
                }
            }

            // The cover's eight colours, as one ribbon (the editor's and the presets' shape).
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin: Tokens.spacingXs
                spacing: 0
                visible: AlbumScheme.active
                Repeater {
                    model: 8
                    delegate: Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconSm
                        topLeftRadius:     index === 0 ? height / 2 : 0
                        bottomLeftRadius:  index === 0 ? height / 2 : 0
                        topRightRadius:    index === 7 ? height / 2 : 0
                        bottomRightRadius: index === 7 ? height / 2 : 0
                        color: Colors.of(QsWindow.window).ansi(index + 1)
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }
                }
            }
        }
    }
}
