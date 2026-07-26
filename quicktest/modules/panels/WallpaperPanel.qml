pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── WallpaperPanel ────────────────────────────────────────────────────────────
// The wallpaper gallery.
//
// ── All logic lives in the Wallpaper service ──────────────────────────────────
// This file used to own a `Process` whose command was ~110 lines of bash concatenated in
// QML, with Python heredocs inside it. Closing the panel mid-apply killed the run and left
// the palette half-written. The pipeline is now `scripts/apply-wallpaper.sh`, driven by the
// `Wallpaper` singleton, and this file only shows things and calls two functions.
//
// ── Progress is shown, not hidden in /tmp ─────────────────────────────────────
// Applying repaints fourteen applications and takes seconds. The old version wrote its log
// to /tmp/wallpaper.log, showed nothing, and reported "applied!" even when steps had failed
// — which is how GTK theming stayed broken for a month. The service parses a step protocol
// and this renders it live, including which steps failed.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Both are PanelHost's: it pins the wallpaper gallery to 535x340 regardless of what
    // this file asks for. It briefly honoured the panel's own 420 and the gallery looked
    // worse for it, so the special case was restored — see PanelHost.heightFor(). Declared
    // to match, rather than asking for a size that will be ignored.
    implicitWidth:  535
    implicitHeight: 340

    property bool listView: false

    readonly property var filtered: {
        const s = searchInput.text.toLowerCase()
        if (s === "") return Wallpaper.wallpapers
        return Wallpaper.wallpapers.filter(w => w.split("/").pop().toLowerCase().includes(s))
    }

    // The gallery gets out of the way while a wallpaper is being applied, and comes back
    // when it succeeds. A FAILED run stays put — hiding it would remove the only account of
    // what went wrong. Same contract as UpdatesPage and StoragePage.
    readonly property bool showProgress: Wallpaper.applying || Wallpaper.lastFailed

    // Step list is collapsed by default and opens itself on failure — the only time the
    // per-step breakdown is what you actually want to see.
    property bool showDetails: false
    onShowProgressChanged: if (!root.showProgress) root.showDetails = false

    Connections {
        target: Wallpaper
        function onLastFailedChanged() { if (Wallpaper.lastFailed) root.showDetails = true }
    }

    // Dismisses the pointer focus from the search field when clicking elsewhere in the
    // panel, so typing doesn't keep going into a box you've visually left.
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (searchInput.activeFocus) searchInput.focus = false
            mouse.accepted = false
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        PanelHeader {
            icon:      Icons.asset("wallpaper")
            title:     "Wallpaper"
            titleTail: "Gallery"
            accent:    Colors.info
            subtitle:  Wallpaper.scanning ? "Scanning…"
                     : root.filtered.length === Wallpaper.wallpapers.length
                     ? Wallpaper.wallpapers.length + " wallpapers"
                     : root.filtered.length + " of " + Wallpaper.wallpapers.length

            // Rescanning the directory FINISHES, so a plain button is right here — unlike
            // the wifi panel's endless scan, which needs a different affordance.
            PanelButton {
                variant: "ghost"
                glyph:   "󰑐"
                enabled: !Wallpaper.scanning
                onActivated: Wallpaper.rescan()
            }

            // ── Grid / list toggle ────────────────────────────────────────────
            // Was a hand-built pair of Rectangles with literal 64/30/6/18 sizing. Now
            // driven by Tokens, so it matches every other segmented control in the shell.
            Rectangle {
                implicitWidth:  Tokens.pillIconWidth + Tokens.spacingXl
                implicitHeight: Tokens.pillHeight + Tokens.spacingSm
                radius: Tokens.radiusSm
                color:  Colors.surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: [
                            { asset: "cozy", list: false },
                            { asset: "list", list: true  }
                        ]
                        delegate: Rectangle {
                            id: modeBtn
                            required property var modelData

                            Layout.fillWidth:  true
                            Layout.fillHeight: true
                            radius: Tokens.radiusXs
                            readonly property bool on: root.listView === modeBtn.modelData.list
                            color: modeBtn.on ? Colors.alpha(Colors.info, 0.30) : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            Image {
                                anchors.centerIn: parent
                                source: Icons.asset(modeBtn.modelData.asset)
                                width:  Tokens.iconMd
                                height: Tokens.iconMd
                                fillMode: Image.PreserveAspectFit
                                opacity: modeBtn.on ? 1.0 : 0.55
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.listView = modeBtn.modelData.list
                            }
                        }
                    }
                }
            }
        }

        // ── Search ────────────────────────────────────────────────────────────
        Surface {
            Layout.fillWidth: true
            visible: !root.showProgress
            elevation: Tokens.elevationNested
            focused: searchInput.activeFocus
            implicitHeight: Tokens.pillHeight + Tokens.spacingMd

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingMd
                spacing: Tokens.spacingMd

                StyledText { text: "󰍉"; variant: "body"; emphasis: "dim" }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: Colors.fg
                    selectionColor: Colors.alpha(Colors.info, 0.35)
                    selectByMouse: true
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLabel
                    verticalAlignment: TextInput.AlignVCenter
                    cursorVisible: activeFocus

                    // Escape clears the field and hands focus back rather than closing the
                    // overview from under you — and because focus returns to an ancestor,
                    // a SECOND Escape then closes the panel as normal.
                    Keys.onEscapePressed: {
                        searchInput.text = ""
                        searchInput.focus = false
                    }
                    // Enter applies the only remaining match. With one result on screen,
                    // reaching for the mouse to click the thing you just typed the name of
                    // is a step for nothing.
                    Keys.onReturnPressed: {
                        if (root.filtered.length === 1) Wallpaper.apply(root.filtered[0])
                    }

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search wallpapers…"
                        variant: "label"
                        emphasis: "dim"
                        visible: searchInput.text.length === 0
                    }
                }

                IconButton {
                    glyph: "󰅖"
                    visible: searchInput.text.length > 0
                    // `clicked`, not `activated` — IconButton and PanelButton use
                    // different signal names; PanelButton is the one with activated().
                    onClicked: searchInput.text = ""
                }
            }
        }

        // ══ Body ══════════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Grid ──────────────────────────────────────────────────────────
            GridView {
                id: grid
                anchors.fill: parent
                anchors.rightMargin: Tokens.spacingMd
                clip: true
                cellWidth:  164
                cellHeight: 115
                model: root.filtered
                cacheBuffer: 500
                maximumFlickVelocity: 2500
                flickDeceleration: 1500

                opacity: !root.listView && !root.showProgress ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                delegate: WallpaperTile {
                    required property var modelData
                    width:  grid.cellWidth
                    height: grid.cellHeight
                    path:   modelData
                }
            }
            Scrollbar { flickable: grid }

            // ── List ──────────────────────────────────────────────────────────
            ListView {
                id: list
                anchors.fill: parent
                anchors.rightMargin: Tokens.spacingMd
                clip: true
                spacing: Tokens.spacingSm
                model: root.filtered

                opacity: root.listView && !root.showProgress ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                delegate: WallpaperRow {
                    required property var modelData
                    width: list.width
                    path:  modelData
                }
            }
            Scrollbar { flickable: list }

            // ── Empty state ───────────────────────────────────────────────────
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingXxl * 2
                spacing: Tokens.spacingSm
                visible: root.filtered.length === 0 && !Wallpaper.scanning && !root.showProgress

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: searchInput.text.length > 0 ? "No matches" : "No wallpapers found"
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: searchInput.text.length > 0
                        ? "Nothing here is called “" + searchInput.text + "”."
                        : "Put images in " + Wallpaper.wallpaperDir + " and rescan."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            // ── Progress ──────────────────────────────────────────────────────
            Flickable {
                id: progressPane
                anchors.fill: parent
                contentHeight: progressCol.implicitHeight
                clip: true

                opacity: root.showProgress ? 1.0 : 0.0
                visible: opacity > 0.005
                interactive: root.showProgress
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                ColumnLayout {
                    id: progressCol
                    width: progressPane.width
                    spacing: Tokens.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Tokens.spacingSm
                        spacing: Tokens.spacingMd

                        BusyDot { running: Wallpaper.applying; tint: Colors.info }
                        StyledText {
                            Layout.fillWidth: true
                            text: Wallpaper.applying
                                ? "Applying " + Wallpaper.applyingPath.split("/").pop() + "…"
                                : Wallpaper.failedCount > 0
                                ? Wallpaper.failedCount + " step"
                                  + (Wallpaper.failedCount !== 1 ? "s" : "") + " failed"
                                : "Finished with errors"
                            variant: "body"
                            font.weight: Font.DemiBold
                            color: Wallpaper.applying ? Colors.fg : Colors.warning
                            elide: Text.ElideRight
                        }
                        // Details are OPT-IN. Fourteen step lines on every single wallpaper
                        // change is noise you have to look past — you only care which step
                        // it was when something went wrong. Auto-opened on failure, for
                        // exactly that reason.
                        PanelButton {
                            variant: "ghost"
                            glyph: root.showDetails ? "󰅃" : "󰅀"
                            label: "Details"
                            onActivated: root.showDetails = !root.showDetails
                        }
                        PanelButton {
                            visible: !Wallpaper.applying
                            variant: "ghost"
                            label: "Dismiss"
                            onActivated: Wallpaper.clearResult()
                        }
                    }

                    Repeater {
                        model: root.showDetails ? Wallpaper.steps : []
                        delegate: RowLayout {
                            id: stepRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            // Glyph carries the state as well as the colour: `danger`
                            // shares a hue with `primary` in this palette, so colour alone
                            // can't be what marks a failure.
                            StyledText {
                                text: stepRow.modelData.status === "ok"   ? "󰄬"
                                    : stepRow.modelData.status === "fail" ? "󰅖"
                                    : stepRow.modelData.status === "skip" ? "󰒲"
                                    : "󰔟"
                                color: stepRow.modelData.status === "ok"   ? Colors.success
                                     : stepRow.modelData.status === "fail" ? Colors.danger
                                     : Colors.fgDim
                                variant: "caption"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: stepRow.modelData.text
                                variant: "caption"
                                emphasis: stepRow.modelData.status === "skip" ? "dim" : "normal"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            Scrollbar { flickable: progressPane }
        }

        // ── Apps that need restarting ─────────────────────────────────────────
        // One prompt for whatever the script found running, rather than naming a single
        // app as if it were the only one that mattered. Zen can't reload userChrome.css,
        // and libadwaita apps (Files, Mission Center) ignore the gtk-theme key the script
        // toggles — different reasons, same remedy, so one prompt.
        //
        // It is always the user's button. The old pipeline killed these outright on every
        // wallpaper change. A plain compact row, not an elevated Surface — the boxed bar
        // broke the panel's shape and read as an alarm; same treatment as ColorSchemePanel.
        RowLayout {
            Layout.fillWidth: true
            visible: Wallpaper.needsRestart && !Wallpaper.applying
            spacing: Tokens.spacingSm

            StyledText { text: "󰜉"; color: Colors.info; variant: "caption" }
            StyledText {
                Layout.fillWidth: true
                text: Wallpaper.restartApps.map(a => a.label).join(", ")
                    + (Wallpaper.restartApps.length === 1 ? " needs" : " need")
                    + " a restart to recolour"
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            PanelButton {
                variant: "ghost"
                glyph: "󰑐"
                label: "Restart"
                onActivated: Wallpaper.restartAll()
            }
            PanelButton {
                variant: "ghost"
                glyph: "󰅖"
                onActivated: Wallpaper.dismissRestart()
            }
        }
    }

    // ── WallpaperTile ─────────────────────────────────────────────────────────
    // One thumbnail in the grid.
    component WallpaperTile: Item {
        id: tile
        property string path: ""

        readonly property string name: tile.path.split("/").pop()
        readonly property bool  isCurrent: Wallpaper.current === tile.name

        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            color: Colors.surfaceContainer
            radius: Tokens.radiusPill
            clip: true

            // The ACTIVE wallpaper is outlined permanently, hover is a separate, brighter
            // state. The old grid marked the current wallpaper not at all — there was no
            // way to tell which one you were looking at.
            border.width: tile.isCurrent || hover.containsMouse ? 2 : 0
            border.color: hover.containsMouse ? Colors.info
                        : tile.isCurrent ? Colors.alpha(Colors.info, 0.55)
                        : "transparent"
            scale: hover.pressed ? 0.95 : hover.containsMouse ? 1.04 : 1.0

            Behavior on scale       { NumberAnimation { duration: Motion.standard
                                                        easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation  { duration: Motion.respond } }
            Behavior on border.width { NumberAnimation { duration: Motion.respond } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingSm
                spacing: Tokens.spacingXs

                Rectangle {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    color:  Colors.alpha(Colors.surface, 0.5)
                    radius: Tokens.radiusSm
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: "file://" + tile.path
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        // Decoded off the UI thread and downscaled at load: these are 4K
                        // files rendered into a 150px cell, and without sourceSize each one
                        // would hold its full decoded size in memory.
                        asynchronous: true
                        cache: true
                        sourceSize.width:  300
                        sourceSize.height: 200
                    }

                    BusyDot {
                        anchors.centerIn: parent
                        running: parent.children[0].status === Image.Loading
                        tint: Colors.info
                    }

                    // Marks the live wallpaper inside the thumbnail, where the eye already
                    // is, rather than only on the border.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.spacingXs
                        width:  Tokens.iconMd
                        height: Tokens.iconMd
                        radius: width / 2
                        color:  Colors.info
                        visible: tile.isCurrent

                        StyledText {
                            anchors.centerIn: parent
                            text: "󰄬"
                            color: Colors.fgOnPrimary
                            variant: "caption"
                        }
                    }

                    // ── Explicit Apply ────────────────────────────────────────
                    // The whole tile is still clickable, but "click the picture" is a
                    // convention you have to already know. A named button on hover says
                    // what the click DOES, and says it where you're already looking.
                    Rectangle {
                        anchors.centerIn: parent
                        implicitWidth:  applyLabel.implicitWidth + Tokens.spacingLg * 2
                        implicitHeight: Tokens.pillHeight
                        radius: Tokens.radiusFull
                        color:  Colors.info
                        opacity: hover.containsMouse && !tile.isCurrent ? 1.0 : 0.0
                        visible: opacity > 0.005
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                        StyledText {
                            id: applyLabel
                            anchors.centerIn: parent
                            text: "Apply"
                            color: Colors.fgOnPrimary
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: tile.name
                    variant: "caption"
                    emphasis: tile.isCurrent ? "normal" : "dim"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !Wallpaper.applying
                onClicked: Wallpaper.apply(tile.path)
            }
        }
    }

    // ── WallpaperRow ──────────────────────────────────────────────────────────
    // One entry in the list view.
    component WallpaperRow: Rectangle {
        id: row
        property string path: ""

        readonly property string name: row.path.split("/").pop()
        readonly property bool  isCurrent: Wallpaper.current === row.name

        implicitHeight: 52
        radius: Tokens.radiusSm
        // `surfaceHigh` IS "that surface, hovered" — the role exists for exactly this. The
        // old row doubled surfaceContainer's own alpha to fake the lift, which stopped
        // meaning anything once the surfaces became opaque: `.a` is 1, so `* 2` clamps
        // straight back to 1 and the hover silently became a no-op.
        color: rowHover.containsMouse ? Colors.surfaceHigh : Colors.surfaceContainer
        border.width: row.isCurrent ? 1 : 0
        border.color: Colors.alpha(Colors.info, 0.55)
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            spacing: Tokens.spacingMd

            Rectangle {
                Layout.preferredWidth:  64
                Layout.fillHeight: true
                radius: Tokens.radiusXs
                color:  Colors.alpha(Colors.surface, 0.5)
                clip: true

                Image {
                    anchors.fill: parent
                    source: "file://" + row.path
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width:  160
                    sourceSize.height: 100
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: row.name
                    variant: "body"
                    elide: Text.ElideMiddle
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.isCurrent ? "Current wallpaper" : "Click to apply"
                    variant: "caption"
                    emphasis: "dim"
                    color: row.isCurrent ? Colors.info : Colors.fgDim
                }
            }

            StyledText {
                visible: row.isCurrent
                text: "󰄬"
                color: Colors.info
                variant: "body"
            }

            // Always present in list view, not only on hover: a list is scanned by reading
            // rather than by pointing, so the action should be visible without hunting for
            // it. Hidden on the active wallpaper, where re-applying is a no-op.
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                visible: !row.isCurrent
                variant: "normal"
                label: "Apply"
                enabled: !Wallpaper.applying
                onActivated: Wallpaper.apply(row.path)
            }
        }

        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !Wallpaper.applying
            // z: -1 is load-bearing. This is declared AFTER the RowLayout, so by default it
            // would sit on top and swallow every click meant for the Apply button — the
            // button would still look interactive and never light up. Pushing it behind
            // lets the button take the click when the pointer is on it, and this handles
            // everywhere else in the row.
            z: -1
            onClicked: Wallpaper.apply(row.path)
        }
    }
}
