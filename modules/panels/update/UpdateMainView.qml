import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── UpdateMainView ── part of UpdatePanel.qml; `panel` is the UpdatePanel it belongs to. ──
ColumnLayout {
    id: mainCol
    required property var panel
    property alias passField: passField
    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: panel.viewState.view === "main"
    opacity: visible ? 1 : 0
    spacing: Tokens.spacingSm
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // Arch news — a manual-intervention post the --noconfirm run can't cope
    // with. Newer than your last upgrade → you haven't seen it.
    UpdateNewsLine {
        Layout.fillWidth: true
        visible: Updates.newsUnread
    }

    // Kernel / graphics module in the list → you'll want to reboot after.
    UpdateRebootBanner {
        Layout.fillWidth: true
        visible: Updates.needsReboot
    }

    // ── The peek: counts, expandable to the real list ─────────────
    Rectangle {
        id: peekCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: peekBody.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: peekCard; active: panel.mainOn; delay: panel.lead; rise: Tokens.spacingMd }
        // Matches the panel's own top-level Behavior on implicitHeight, so the card, this
        // surface and the list below all ease on the same curve — three unsynced snaps was
        // what read as "rough".
        Behavior on implicitHeight { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }

        ColumnLayout {
            id: peekBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            // Disclosure row — always visible, the whole thing is the hit target.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconLg

                HoverHandler { id: peekHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: panel.peekExpanded = !panel.peekExpanded }

                RowLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: "keyboard_arrow_down"
                        font.pixelSize: Tokens.iconMd
                        rotation: panel.peekExpanded ? 180 : 0
                        color: peekHover.hovered ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Motion.spatial
                                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                            }
                        }
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.checking ? "Checking…"
                            : Updates.hasError ? "Package database unavailable"
                            : "<font color=\"" + panel.officialTint + "\">" + Updates.count + " official</font>"
                              + (Updates.helper ? "  ·  <font color=\"" + panel.aurTint + "\">"
                                  + Updates.aurCount + " AUR</font>" : "")
                              + (Updates.hasFlatpak ? "  ·  <font color=\"" + panel.flatpakTint + "\">"
                                  + Updates.flatpakCount + " Flatpak</font>" : "")
                        rich: true
                        variant: "label"
                        emphasis: "muted"
                        elide: Text.ElideRight
                    }
                    Badge {
                        visible: Updates.heldPending.length > 0
                        label: Updates.heldPending.length + " held"
                        tint: Colors.of(QsWindow.window).warning
                    }
                }
            }

            // Official/AUR/Flatpak, proportional — the same composition
            // strip UpdatesPage opens with, so a glance at either the
            // panel or the full settings view reads the same "how much,
            // of what kind" before the exact counts above are legible.
            // Shown ahead of the list whether or not it's expanded.
            UpdateCompositionStrip {
                host: panel
                Layout.fillWidth: true
                visible: !Updates.checking && !Updates.hasError
                official: Updates.count
                aur:      Updates.aurCount
                flatpak:  Updates.flatpakCount
            }

            // ── The list ──────────────────────────────────────────
            // Folds away to nothing; opens to a source switch, a name filter (once there are
            // enough to need one), the tick helpers and the rows, capped and scrolling.
            Item {
                id: peekWrap
                Layout.fillWidth: true
                Layout.preferredHeight: panel.peekExpanded ? peekList.implicitHeight : 0
                Layout.topMargin: panel.peekExpanded ? 0 : -Tokens.spacingSm
                Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
                Behavior on Layout.topMargin       { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
                visible: Layout.preferredHeight > 0
                clip: true

                ColumnLayout {
                    id: peekList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Tokens.spacingSm

                    SegmentSwitch {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: panel.sourceModel.length > 2
                        accent: Colors.of(QsWindow.window).info
                        model: panel.sourceModel
                        current: panel.srcFilter
                        onPicked: (v) => panel.srcFilter = v
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        visible: Updates.total > 8 || panel.tickableShown > 0

                        InputField {
                            Layout.fillWidth: true
                            visible: Updates.total > 8
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            icon: "search"
                            placeholder: "Filter " + Updates.total + " updates…"
                            onEdited: (v) => panel.query = v
                            onKeyPressed: (event) => {
                                if (event.key !== Qt.Key_Escape || panel.query === "") return
                                clear(); panel.query = ""; event.accepted = true
                            }
                        }
                        Item { Layout.fillWidth: true; visible: Updates.total <= 8 }
                        // Tick every AUR / Flatpak package on show; clear the ticks.
                        ChipTray {
                            ChipButton {
                                visible: panel.tickableShown > 0
                                symbol:  "checklist"
                                label:   panel.selectedCount > 0 ? String(panel.selectedCount) : ""
                                on:      panel.selectedCount > 0
                                tint:    Colors.of(QsWindow.window).focus
                                onActivated: panel.selectedCount > 0 ? panel.clearSelection() : panel.selectShown()
                            }
                        }
                    }

                    // The scrollbar is a SIBLING of the Flickable, inside a plain Item: it anchors to
                    // the Flickable, and as a layout child it logged "anchors on an item that is managed
                    // by a layout" at every start.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(rowsCol.implicitHeight, 190)

                    Flickable {
                        id: peekFlick
                        anchors.fill: parent
                        clip: true
                        contentHeight: rowsCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: rowsCol
                            width: peekFlick.width
                            spacing: 0

                            Repeater {
                                model: panel.rows
                                delegate: UpdatePkgRow {
                                    host: panel
                                    required property var modelData
                                    width: rowsCol.width
                                    row: modelData
                                }
                            }
                            StyledText {
                                visible: panel.rows.length === 0
                                width: rowsCol.width
                                topPadding: Tokens.spacingMd
                                bottomPadding: Tokens.spacingMd
                                horizontalAlignment: Text.AlignHCenter
                                text: panel.query !== "" ? "No update matches “" + panel.query + "”" : "Nothing here"
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                    }
                    Scrollbar { flickable: peekFlick }
                    }
                }
            }
        }
    }

    // Held summary — one line, one click to clear the lot.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Updates.heldPending.length > 0
        spacing: Tokens.spacingSm
        MaterialIcon { name: "pause"; fill: 1; font.pixelSize: Tokens.iconSm; color: Colors.of(QsWindow.window).warning }
        StyledText {
            Layout.fillWidth: true
            text: Updates.heldPending.length + " package"
                + (Updates.heldPending.length === 1 ? "" : "s") + " held back this run"
            variant: "caption"
            emphasis: "dim"
        }
        ChipTray {
            ChipButton {
                label: Translation.tr("Clear")
                tint:  Colors.of(QsWindow.window).warning
                onActivated: Updates.clearHolds()
            }
        }
    }

    // ── The way in ────────────────────────────────────────────────
    ColumnLayout {
        id: mainActions
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: Tokens.spacingXs
        spacing: Tokens.spacingSm
        opacity: 0
        ViewEnter { target: mainActions; active: panel.mainOn; delay: panel.lead + Motion.respond; rise: Tokens.spacingMd }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            InputField {
                id: passField
                Layout.fillWidth: true
                implicitHeight: panel._fieldH
                cornerRadius: implicitHeight / 2
                icon: "lock"
                secret: true
                placeholder: Translation.tr("sudo password…")
                onAccepted: panel.selectedCount > 0 ? panel._confirmSelected() : panel._confirmSysUpdate()
                onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel._escClose(); event.accepted = true } }
            }
            UpdateShellUpdateButton { host: panel }
        }

        // The primary button is "everything" until you tick something, then it
        // installs the subset — same runner, one fewer trip to Settings.
        UpdateActionButton {
            host: panel
            icon:   panel.selectedCount > 0 ? "checklist" : "download"
            text:   panel.selectedCount > 0
                  ? "Install " + panel.selectedCount + " selected"
                  : "Update everything" + (panel.activePending > 0 ? "  (" + panel.activePending + ")" : "")
            disabled: panel.selectedCount > 0
                    ? (panel.selectionNeedsPassword && passField.text.length === 0)
                    : (passField.text.length === 0 || panel.activePending <= 0)
            clickHandler: function() {
                panel.selectedCount > 0 ? panel._confirmSelected() : panel._confirmSysUpdate()
            }
        }

        UpdateActionButton {
            host: panel
            icon: "extension"
            text: Translation.tr("Update Discord (Vencord)")
            primary: false
            disabled: passField.text.length === 0
            clickHandler: function() { panel._confirmVencord(passField.text) }
        }
    }
}
