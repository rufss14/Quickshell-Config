pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// ── LockPage — Desktop › Lock screen ──────────────────────────────────────────
// The lock screen: what it shows, what sits behind it, when it appears, what it
// authenticates against, and who it says you are.
//
// This is the one feature in the shell that can lock you out of your own machine —
// the PAM service name in particular is a free-text field whose wrong value means
// "a password box that can never accept a password". So the page reports what the
// system says (Lock.pamState, probed by the service) rather than what we hoped.
//
// ── Each block says where it lands ────────────────────────────────────────────
// There is no drawn schematic of the lock: a picture of rectangles is a second implementation that
// starts lying at the first change. Each chip carries its POSITION ("bottom centre", "right edge",
// "across the bottom") as its tip, taken from where modules/lock/LockScreen.qml actually anchors that block.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The same circle the lock draws, so what you see here is what you'll see there —
    // including the monogram when nothing is set.
    readonly property int avatarSize: 64

    readonly property int shownCount:
          (Config.lockShowMedia         ? 1 : 0)
        + (Config.lockShowNotifications ? 1 : 0)
        + (Config.lockShowStats         ? 1 : 0)
        + (Config.lockShowCalendar      ? 1 : 0)
        + (Config.lockShowDiscord       ? 1 : 0)
        + (Config.lockShowPower         ? 1 : 0)
        + (Config.lockShowBrightness    ? 1 : 0)
        + (Config.lockShowCava          ? 1 : 0)

    // ── The picker ────────────────────────────────────────────────────────────
    // In the shell, not a zenity window: a GTK dialog in someone else's theme on top
    // of a shell whose point is looking like itself, and a core setting depending on
    // an optional package. Same FolderListModel + GridView idiom as the wallpaper page.
    readonly property string home: Quickshell.env("HOME") || ""
    property bool picking: false
    property url  browseFolder: "file://" + root.home

    function openPicker() {
        // Start where the current picture lives — changing an avatar usually means
        // picking its neighbour, not starting from home again.
        const cur = Config.lockAvatar
        if (cur !== "" && Lock.avatarState === "ok") {
            const cut = cur.lastIndexOf("/")
            if (cut > 0) root.browseFolder = "file://" + cur.substring(0, cut)
        }
        root.picking = true
    }

    function parentFolder(f) {
        const s = String(f)
        const cut = s.lastIndexOf("/")
        return (cut > 7) ? s.substring(0, cut) : "file:///"   // keep "file://" intact
    }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰌾"
        title:     Translation.tr("Lock")
        titleTail: "screen"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  (Config.lockIdleEnabled
                        ? Translation.tr("Locks itself after %1 minutes idle").arg(Config.lockIdleMinutes)
                        : Lock.sleepArmed ? Translation.tr("Locks before sleep, or when you ask")
                        : Translation.tr("Locks only when you ask it to"))
                   + "  ·  " + Translation.tr("%1 of 8 blocks shown").arg(root.shownCount)

        // Hold, not click: a single press that locks the machine is one stray click
        // away from annoying. In the header because it is the page's one action, and a
        // hold can't be triggered by a mis-click on the way to a switch.
        actions: HoldButton {
            capsule:   true
            label:     Translation.tr("Hold to lock")
            busyLabel: Translation.tr("Locking…")
            glyph:     "󰌾"
            accent:    Colors.of(QsWindow.window).warning
            // The warning tint and the sweep say what it is; an outline on top would be a second voice.
            borderWidth: 0
            enabled:   Lock.pamState !== "missing" && !Lock.locked
            onConfirmed: Lock.lock()
        }

        // ══ What it shows ══════════════════════════════════════════════════════
        // A set of yes/no's, so chips in one segment: eight switch rows with a position each was the
        // tallest group on the page. Where each block sits on the lock screen is its chip's tip
        // (taken from where LockScreen.qml anchors it).
        Section {
            grouped:  true
            symbol:   "visibility"
            title:    Translation.tr("What it shows")
            subtitle: Translation.tr("%1 of 8 blocks on").arg(root.shownCount)
            help:     Translation.tr("Everything on the lock screen is readable by whoever is standing at the machine.")

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                ToggleChip {
                    symbol: "music_note"
                    label:  Translation.tr("Now playing")
                    hint: Translation.tr("Bottom centre: the track, its cover and controls.")
                    active: Config.lockShowMedia
                    onToggled: Config.lockShowMedia = !Config.lockShowMedia
                }
                ToggleChip {
                    symbol: "notifications"
                    label:  Translation.tr("Notifications")
                    hint: Translation.tr("Right edge, with their full text, to anyone at the screen.")
                    active: Config.lockShowNotifications
                    onToggled: Config.lockShowNotifications = !Config.lockShowNotifications
                }
                ToggleChip {
                    symbol: "speed"
                    label:  Translation.tr("System stats")
                    hint: Translation.tr("Top centre.")
                    active: Config.lockShowStats
                    onToggled: Config.lockShowStats = !Config.lockShowStats
                }
                ToggleChip {
                    symbol: "calendar_month"
                    label:  Translation.tr("Calendar")
                    hint: Translation.tr("Bottom left.")
                    active: Config.lockShowCalendar
                    onToggled: Config.lockShowCalendar = !Config.lockShowCalendar
                }
                ToggleChip {
                    symbol: "headset"
                    label:  Translation.tr("Discord call")
                    hint: Translation.tr("Top centre, while you're in a call.")
                    active: Config.lockShowDiscord
                    onToggled: Config.lockShowDiscord = !Config.lockShowDiscord
                }
                ToggleChip {
                    symbol: "power_settings_new"
                    label:  Translation.tr("Session actions")
                    hint: Translation.tr("Left edge: suspend, restart, log out. Log out discards unsaved work.")
                    active: Config.lockShowPower
                    onToggled: Config.lockShowPower = !Config.lockShowPower
                }
                ToggleChip {
                    symbol: "brightness_6"; label: Translation.tr("Brightness")
                    hint: Translation.tr("Bottom right.")
                    active: Config.lockShowBrightness
                    onToggled: Config.lockShowBrightness = !Config.lockShowBrightness
                }
                ToggleChip {
                    symbol: "equalizer"
                    label:  Translation.tr("Audio spectrum")
                    hint: Translation.tr("Across the bottom.")
                    active: Config.lockShowCava
                    onToggled: Config.lockShowCava = !Config.lockShowCava
                }
            }

            // Not a chip: it is not a block of its own but a setting of Now playing, so it is a row
            // that exists only while that block is on, and the chips stay "N of 8".
            SettingRow {
                visible: Config.lockShowMedia
                rowTap:  true
                label:   Translation.tr("Lyrics on YouTube")
                detail:  Config.lockLyricsOnYouTube ? Translation.tr("Shown for videos as well as music")
                                                    : Translation.tr("Music players only")
                help:    Translation.tr("Show lyrics under Now playing for YouTube videos too, not only music players.")
                onTapped: Config.lockLyricsOnYouTube = !Config.lockLyricsOnYouTube

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.lockLyricsOnYouTube
                    onToggled: Config.lockLyricsOnYouTube = !Config.lockLyricsOnYouTube
                }
            }

            // Only when there is something to warn about. Notifications show what they
            // SAY, not just how many; logging out discards unsaved work in every window
            // behind the lock.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Config.lockShowNotifications || Config.lockShowPower
                text: Config.lockShowNotifications && Config.lockShowPower
                        ? Translation.tr("Notifications show their full text, and log out discards unsaved work.")
                    : Config.lockShowNotifications
                        ? Translation.tr("Notifications show their full text to anyone at the screen.")
                        : Translation.tr("Session actions include log out, which discards unsaved work.")
                variant:  "caption"
                color:    Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }
        }

        // ══ Authentication ════════════════════════════════════════════════════
        // The group that can lock you out of your own machine, so its badge wears the warning colour:
        // the field and its verdict, then the way back in.
        Section {
            grouped:  true
            symbol:   "key"
            title:    Translation.tr("Authentication")
            subtitle: Translation.tr("PAM: %1").arg(Config.lockPamConfig)
            help:     Translation.tr("Which PAM stack the password box asks. \"login\" exists everywhere. If the lock ever refuses a correct password: Ctrl+Alt+F2, log in, and run loginctl unlock-session.")
            accent:   Colors.of(QsWindow.window).warning

            // A text field rather than a list of /etc/pam.d: fifty entries, a
            // handful of login stacks — a long list of wrong answers with the
            // right one buried.
            SettingRow {
                label:  Translation.tr("PAM service")
                detail: Translation.tr("Press Enter to set it")

                RowLayout {
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        cornerRadius: implicitHeight / 2
                        id: pamField
                        Layout.preferredWidth: Tokens.fieldHeight * 6
                        placeholder: "login"
                        seed: Config.lockPamConfig
                        invalid: Lock.pamState === "missing"
                        // Enter only, never per keystroke or on focus loss: typing
                        // "login" passes through "l", "lo"… and each would point the
                        // lock at a service that doesn't exist.
                        onAccepted: function (v) {
                            const t = v.trim()
                            if (t !== "") Config.lockPamConfig = t
                        }
                    }
                    PanelButton {
                        capsule: true
                        variant: "normal"
                        label:   Translation.tr("Set")
                        enabled: pamField.text.trim() !== "" && pamField.text.trim() !== Config.lockPamConfig
                        onActivated: Config.lockPamConfig = pamField.text.trim()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                MaterialIcon {
                    glyph: Lock.pamState === "ok"      ? "󰄬"
                        : Lock.pamState === "missing" ? "󰀦"
                        :                               "󰇉"
                    variant: "label"
                    color: Lock.pamState === "ok"      ? Colors.of(QsWindow.window).success
                         : Lock.pamState === "missing" ? Colors.of(QsWindow.window).danger
                         :                               Colors.of(QsWindow.window).fgDim
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Lock.pamState === "ok"
                            ? Translation.tr("/etc/pam.d/%1 exists.").arg(Config.lockPamConfig)
                        : Lock.pamState === "missing"
                            ? Translation.tr("/etc/pam.d/%1 doesn't exist, so the lock couldn't authenticate.").arg(Config.lockPamConfig)
                            : Translation.tr("Checking…")
                    variant: "caption"
                    color: Lock.pamState === "missing" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                    wrapMode: Text.WordWrap
                }
            }

            // Only when something went wrong.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Lock.lastError !== ""
                text: Translation.tr("Last problem: %1").arg(Lock.lastError)
                variant: "caption"
                color: Colors.of(QsWindow.window).danger
                wrapMode: Text.WordWrap
            }

            // ext-session-lock-v1 keeps the session locked if the locker dies
            // without unlocking. A broken lock isn't "no lockscreen", it's "locked
            // out" — and that's the worst moment to be searching for these lines.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Translation.tr("Locked out? Ctrl+Alt+F2, log in, run  loginctl unlock-session")
                variant: "caption"
                font.family: Tokens.fontMono
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ══ Background ════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "wallpaper"
            title:    Translation.tr("Background")
            subtitle: Config.lockBackdrop === "image" ? Translation.tr("Wallpaper")
                    : Config.lockBackdrop === "none"  ? Translation.tr("Colour")
                    :                                   Translation.tr("Desktop")
            help:     Translation.tr("What sits behind the clock. A running Wallpaper Engine scene shows as its blurred preview: the renderer publishes no still of the live frame.")

            TabStrip {
                Layout.fillWidth: true
                connected: true
                // Every name here has an icons.js fallback, so a machine without the
                // Material Symbols font gets a glyph rather than a "?".
                model: [
                    { value: "auto",  label: Translation.tr("Desktop"),   icon: "monitor" },
                    { value: "image", label: Translation.tr("Wallpaper"), icon: "wallpaper" },
                    { value: "none",  label: Translation.tr("Colour"),    icon: "palette" }
                ]
                current: Config.lockBackdrop
                onPicked: function (v) { Config.lockBackdrop = v }
            }

            SettingRow {
                visible: Config.lockBackdrop === "auto"
                rowTap: true
                label:  Translation.tr("Animate the scene")
                detail: Config.lockSceneAnimate ? Translation.tr("Its preview loops") : Translation.tr("Holds one frame")
                help:   Translation.tr("Off holds one frame of the scene's preview, the only real cure for its short loop.")
                onTapped: Config.lockSceneAnimate = !Config.lockSceneAnimate

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.lockSceneAnimate
                    onToggled: Config.lockSceneAnimate = !Config.lockSceneAnimate
                }
            }
        }

        // ══ When it locks ═════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "lock_clock"
            title:    Translation.tr("Automatic locking")
            subtitle: Config.lockIdleEnabled
                      ? Translation.tr("After %1 minutes with no input").arg(Config.lockIdleMinutes)
                      : Lock.sleepArmed ? Translation.tr("Before sleep, and when you ask")
                      : Translation.tr("Only when you ask it to")

            // Disabled with the reason when systemd-inhibit or gdbus is missing (Lock.sleepBlocker).
            SettingRow {
                enabled: Lock.sleepBlocker === ""
                opacity: enabled ? 1 : 0.4
                rowTap:  true
                label:   Translation.tr("Lock before sleep")
                detail:  Lock.sleepBlocker !== "" ? Lock.sleepBlocker
                         : Config.lockOnSleep ? Translation.tr("Wakes to the lock screen") : Translation.tr("Wakes to your session")
                help:    Translation.tr("Locks as the machine suspends or hibernates, so it wakes to the lock screen.")
                onTapped: Config.lockOnSleep = !Config.lockOnSleep

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.lockOnSleep
                    onToggled: Config.lockOnSleep = !Config.lockOnSleep
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Lock when idle")
                detail: Config.lockIdleEnabled ? Translation.tr("After %1 minutes").arg(Config.lockIdleMinutes) : Translation.tr("Never locks by itself")
                help:   Translation.tr("Leave this off until you've tested unlocking. The bar's idle pill and gamemode hold it off.")
                onTapped: Config.lockIdleEnabled = !Config.lockIdleEnabled

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.lockIdleEnabled
                    onToggled: Config.lockIdleEnabled = !Config.lockIdleEnabled
                }
            }

            // SliderRow: whole minutes are a number you land on.
            SliderRow {
                enabled: Config.lockIdleEnabled
                opacity: enabled ? 1 : 0.4
                label:   Translation.tr("After")
                from:    1
                to:      120
                step:    1
                value:   Config.lockIdleMinutes
                readout: Config.lockIdleMinutes + "m"
                numberWidth: 44
                onCommit: function (v) { Config.lockIdleMinutes = Math.round(v) }
            }
        }

        // ══ Profile picture ═══════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "account_circle"
            title:    Translation.tr("Profile picture")
            subtitle: Config.lockAvatar === "" ? Translation.tr("Default") : Translation.tr("Your own")
            help:     Translation.tr("Lock screen only. Nothing is written to ~/.face.")

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                // The picture sits on a hairline canvas: the one place an outline is allowed.
                Item {
                    Layout.preferredWidth:  root.avatarSize
                    Layout.preferredHeight: root.avatarSize

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)
                        border.width: Tokens.borderWidth
                        border.color: Lock.avatarState === "missing"
                                        ? Colors.of(QsWindow.window).danger
                                        : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).text, 0.28)

                        StyledText {
                            anchors.centerIn: parent
                            visible: preview.status !== Image.Ready
                            text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                            variant: "headline"
                            font.weight: Font.Medium
                            color: Colors.of(QsWindow.window).primary
                        }
                    }

                    // Masked, not clipped — `clip` is rectangular and would leave
                    // square corners outside the circle.
                    Item {
                        anchors.fill: parent
                        anchors.margins: Tokens.borderWidth
                        layer.enabled: true
                        layer.smooth:  true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource:  previewMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin:  1.0
                        }

                        Image {
                            id: preview
                            anchors.fill: parent
                            source: Lock.avatarState === "ok" ? "file://" + Config.lockAvatar : ""
                            sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            mipmap: true
                            smooth: true
                            visible: preview.status === Image.Ready
                        }
                    }

                    Item {
                        id: previewMask
                        anchors.fill: parent
                        anchors.margins: Tokens.borderWidth
                        layer.enabled: true
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "white"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        text: Config.lockAvatar === ""
                                ? Translation.tr("Using ~/.face or AccountsService, or your initial if neither exists")
                            : Lock.avatarState === "missing"
                                ? Translation.tr("That file is gone. The lock shows your initial instead.")
                                : Config.lockAvatar
                        variant: "caption"
                        color: Lock.avatarState === "missing" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                        elide: Text.ElideMiddle
                    }

                    RowLayout {
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        PanelButton {
                            capsule: true
                            variant: "normal"
                            glyph:   "󰉏"
                            label:   Translation.tr("Choose…")
                            onActivated: root.openPicker()
                        }
                        PanelButton {
                            capsule: true
                            variant: "ghost"
                            label:   Translation.tr("Use default")
                            enabled: Config.lockAvatar !== ""
                            onActivated: Config.lockAvatar = ""
                        }
                    }
                }
            }
        }
    }

    // ══ The picture browser ═══════════════════════════════════════════════════
    // Over the page rather than beside it: it's a mode, not a section, and it borrows
    // the whole width so the grid is worth looking at.
    Rectangle {
        anchors.fill: parent
        visible: root.picking
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.72)

        // Swallows clicks aimed at the page underneath; clicking outside closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.picking = false
        }

        Surface {
            anchors.centerIn: parent
            width:  Math.min(parent.width  - Tokens.spacingXxl * 2, 720)
            height: Math.min(parent.height - Tokens.spacingXxl * 2, 520)
            elevation: Tokens.elevationPopup
            cornerRadius: Tokens.radiusCard

            // The card itself must not close the browser.
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    PanelButton {
                        capsule: true
                        variant: "ghost"
                        symbol: "arrow_upward"
                        // "file:///" is the root; there is nowhere above it.
                        enabled: String(root.browseFolder) !== "file:///"
                        onActivated: root.browseFolder = root.parentFolder(root.browseFolder)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        // The leading "file://" is machinery, not a path.
                        text: String(root.browseFolder).replace("file://", "")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideMiddle
                    }
                    PanelButton {
                        capsule: true
                        variant: "ghost"
                        label: Translation.tr("Home")
                        enabled: root.home !== ""
                        onActivated: root.browseFolder = "file://" + root.home
                    }
                    PanelButton {
                        capsule: true
                        variant: "ghost"
                        symbol: "close"
                        onActivated: root.picking = false
                    }
                }

                Divider { Layout.fillWidth: true }

                Item {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true

                    FolderListModel {
                        id: fsModel
                        folder: root.browseFolder
                        showDirs: true
                        showDirsFirst: true
                        showFiles: true
                        showDotAndDotDot: false
                        showHidden: true          // ~/.face lives in a dotfile
                        caseSensitive: false      // so *.jpg matches .JPG
                        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", ".face", ".face.icon"]
                    }

                    GridView {
                        id: fileGrid
                        anchors.fill: parent
                        clip: true
                        model: fsModel
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: fileGrid.cellHeight * 2

                        readonly property int minCell: 150
                        property int cols: Math.max(2, Math.floor(width / fileGrid.minCell))
                        cellWidth:  Math.floor(width / fileGrid.cols)
                        cellHeight: 116

                        delegate: Item {
                            id: cell
                            required property string fileName
                            required property string filePath
                            required property bool   fileIsDir

                            width:  fileGrid.cellWidth
                            height: fileGrid.cellHeight

                            readonly property bool picked:
                                !cell.fileIsDir && Config.lockAvatar === cell.filePath

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingXs
                                radius: Tokens.radiusSm
                                color: Colors.of(QsWindow.window).surface
                                border.width: cell.picked ? 2 : Tokens.borderWidth
                                border.color: cell.picked       ? Colors.of(QsWindow.window).primary
                                            : cellHover.hovered ? Colors.of(QsWindow.window).outlineFocus
                                            :                     Colors.of(QsWindow.window).outline
                                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                                ClippingRectangle {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.borderWidth
                                    anchors.bottomMargin: nameText.implicitHeight + Tokens.spacingXs * 2
                                    radius: Tokens.radiusSm - Tokens.borderWidth
                                    color: "transparent"

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        glyph: "󰉋"
                                        variant: "title"
                                        color: Colors.of(QsWindow.window).focus
                                        visible: cell.fileIsDir
                                    }

                                    Image {
                                        anchors.fill: parent
                                        visible: !cell.fileIsDir
                                        source: cell.fileIsDir ? "" : ("file://" + cell.filePath)
                                        fillMode: Image.PreserveAspectCrop
                                        // Decoded at the drawn size — a folder of 4K photos
                                        // would otherwise decode each at full resolution.
                                        sourceSize: Qt.size(fileGrid.cellWidth * 2, fileGrid.cellHeight * 2)
                                        asynchronous: true
                                        mipmap: true
                                        smooth: true
                                    }
                                }

                                StyledText {
                                    id: nameText
                                    anchors.left:   parent.left
                                    anchors.right:  parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.spacingXs
                                    horizontalAlignment: Text.AlignHCenter
                                    text: cell.fileName
                                    variant: "micro"
                                    emphasis: "dim"
                                    elide: Text.ElideMiddle
                                }
                            }

                            HoverHandler { id: cellHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (cell.fileIsDir) {
                                        root.browseFolder = "file://" + cell.filePath
                                    } else {
                                        Config.lockAvatar = cell.filePath
                                        root.picking = false
                                    }
                                }
                            }
                        }
                    }

                    Scrollbar { flickable: fileGrid }

                    StyledText {
                        anchors.centerIn: parent
                        visible: fsModel.status === FolderListModel.Ready && fsModel.count === 0
                        text: Translation.tr("No pictures or folders here.")
                        variant: "body"
                        emphasis: "dim"
                    }
                }
            }
        }
    }
}
