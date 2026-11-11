pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/treemap.js" as Treemap

// ── StoragePage — System › Storage ────────────────────────────────────────────
// What's using the disks, what can be given back, and what's installed on purpose.
//
// ── Rebuilt around the map (2026-10-26) ───────────────────────────────────────
// It was a column of bars and a list of folders by name. A folder's size is a ratio
// of the whole, and a list of bars hides that the biggest one is most of it. So the
// home folder is now a SPACE MAP: a squarified treemap (services/treemap.js) whose
// tiles are the biggest folders, each as large as its share. Hover for the path.
//
//     ┌ disks — one capacity bar each, the root disk broken down by what fills it ┐
//     ├ space map of $HOME ─────────────────────────┬ reclaim — caches, logs …   ┤
//     └─────────────────────────────────────────────┴ password, then Clean        ┘
//
// Disks | Packages is a header switch: related questions ("where did my space go" /
// "what did I install and do I still want it"), but two different pages of answers.
//
// ── Trash and app caches are reported, not offered ────────────────────────────
// They show up on the map and get no button — see Storage.qml. Packages are the
// deliberate exception: uninstalling a package you asked for is an ordinary decision
// about your own system (you can always reinstall), and it gets the same two-step
// "armed" confirm and sudo gate every cleanup here gets.
//
// ── Packages: explicit only, split by where they came from ────────────────────
// `pacman -Qei` — installed directly, not pulled in as a dependency. A full `-Q` is
// thousands of lines nobody can judge one by one; orphaned dependencies are already
// their own cleanup. Official vs AUR is `pacman -Qm` (foreign), computed once in
// scripts/packages.sh. Removal reuses Storage's reclaim runner (`pacman -Rns` wherever
// the package came from; Flatpak goes through polkit), so there is no AUR helper to
// detect here.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    Component.onCompleted:   Storage.acquire()
    Component.onDestruction: Storage.release()

    onVisibleChanged: if (root.visible) Storage.refresh()

    readonly property bool hasRun: Storage.runBusy || Storage.runLog.length > 0
    property bool showLog: false

    onHasRunChanged: {
        if (!root.hasRun) return
        root.showLog = true
        clearAfterFade.stop()
    }

    Timer {
        running: Storage.runDone && !Storage.runBusy && Storage.runExit === 0
        interval: 2600
        onTriggered: root.returnToList()
    }

    function returnToList() {
        root.showLog = false
        clearAfterFade.restart()
    }

    Timer {
        id: clearAfterFade
        interval: Motion.standard + 40
        onTriggered: Storage.clearRun()
    }

    // "disks" | "packages" — resets to "disks" every time the page is (re)built,
    // same as WallpaperPage's `source`: it's a view choice for this visit, not a
    // preference worth persisting to Config.
    property string section: "disks"

    // One password for both tabs — see the PasswordField component below for how
    // its two instances (Reclaim column, Packages toolbar) stay in sync.
    property string sudoPass: ""
    readonly property bool locked: root.sudoPass.length === 0

    // "official" | "aur" | "flatpak"
    property string pkgSource: "official"
    property string pkgQuery: ""

    // Packages.qml doesn't exist — this scans lazily, the first time the tab is
    // actually opened, same reasoning as scanHome(): no point paying pacman -Qei
    // on every Storage visit when most opens are just "how full are my disks".
    onSectionChanged: {
        if (root.section === "packages" && !Storage.hasScannedPackages
            && !Storage.packagesScanning)
            Storage.scanPackages()
    }

    // ── The header's own reading ──────────────────────────────────────────────
    // Free space on the root filesystem plus anything the reclaimers could give back:
    // the two numbers this page exists to answer, stated before you read a gauge.
    readonly property string freeText: {
        const fs = Storage.filesystems ?? []
        const rootFs = fs.find(f => f.mount === "/") ?? fs[0]
        if (!rootFs) return "Where the space went, and what can be given back"
        const free = Storage.bytes(rootFs.avail) + " free on " + rootFs.mount
        return Storage.reclaimableBytes > 0
            ? free + "  ·  " + Storage.bytes(Storage.reclaimableBytes) + " reclaimable"
            : free
    }

    readonly property var officialPackages: Storage.packages.filter(p => p.source === "official")
    readonly property var aurPackages:      Storage.packages.filter(p => p.source === "aur")
    readonly property var flatpakPackages:  Storage.packages.filter(p => p.source === "flatpak")
    readonly property var sourcePackages: root.pkgSource === "aur"     ? root.aurPackages
                                         : root.pkgSource === "flatpak" ? root.flatpakPackages
                                         : root.officialPackages

    readonly property var filteredPackages: {
        const q = root.pkgQuery.trim().toLowerCase()
        if (q === "") return root.sourcePackages
        return root.sourcePackages.filter(p =>
            p.name.toLowerCase().indexOf(q) !== -1
            || p.id.toLowerCase().indexOf(q) !== -1
            || p.description.toLowerCase().indexOf(q) !== -1)
    }

    // ── Multi-select, by id ────────────────────────────────────────────────────
    // Selection is global across the Official/AUR/Flatpak tabs rather than reset
    // per tab — Storage.uninstallPackages() already splits a mixed batch by
    // source into the right commands (see Storage.qml), so there's no reason to
    // make the UI pretend a cross-tab selection is impossible.
    property var selectedIds: []

    function isSelected(id) { return root.selectedIds.indexOf(id) !== -1 }
    function toggleSelect(id) {
        root.selectedIds = root.isSelected(id)
            ? root.selectedIds.filter(x => x !== id)
            : root.selectedIds.concat([id])
    }
    function deselect(ids) {
        root.selectedIds = root.selectedIds.filter(id => ids.indexOf(id) === -1)
    }

    readonly property bool allFilteredSelected: root.filteredPackages.length > 0
        && root.filteredPackages.every(p => root.isSelected(p.id))

    function toggleSelectAllFiltered() {
        const ids = root.filteredPackages.map(p => p.id)
        root.selectedIds = root.allFilteredSelected
            ? root.selectedIds.filter(id => ids.indexOf(id) === -1)
            : root.selectedIds.concat(ids.filter(id => !root.isSelected(id)))
    }

    readonly property bool selectionNeedsPassword: Storage.packagesNeedPassword(root.selectedIds)

    property bool bulkArmed: false
    Timer { id: bulkDisarm; interval: 4000; onTriggered: root.bulkArmed = false }

    // Shared by the header row and every data row so the columns actually line
    // up like a table instead of drifting with each row's own content width.
    readonly property int pkgCheckboxW: 20
    // The name column is NOT capped any more: a cap (380) left the leftover space for
    // the layout to hand out, and the header and the rows handed it out differently —
    // "Version" sat ~100px left of the versions under it. The page column itself is
    // capped now (SettingsCard's maxPageWidth), so an uncapped name can't strand the
    // other columns at the far edge of a fullscreen window.
    readonly property int pkgVersionW:  110
    readonly property int pkgSizeW:     70
    readonly property int pkgActionW:   100

    // Segment colours for the composition strip. Cycled by index so adjacent slices stay
    // distinguishable; "Other" and "Free" are deliberately NOT in the cycle, because they
    // aren't things — they're the remainder and the gap.
    readonly property var segmentColors: [
        Colors.of(QsWindow.window).focus, Colors.of(QsWindow.window).info, Colors.of(QsWindow.window).warning, Colors.of(QsWindow.window).ramp5, Colors.of(QsWindow.window).success
    ]

    function segmentColor(kind, index) {
        if (kind === "free")     return Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
        if (kind === "reserved") return Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
        if (kind === "other")    return Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.28)
        return root.segmentColors[index % root.segmentColors.length]
    }


    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰋊"
        title:     Translation.tr("Storage")
        titleTail: root.section === "packages" ? "· packages" : ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.section === "packages"
                   ? (Storage.hasScannedPackages
                      ? Storage.packages.length + " installed on purpose — not pulled in as dependencies"
                      : "Scanning…")
                   : root.freeText

        actions: [
            BusyDot { running: Storage.packagesScanning || Storage.probing || Storage.scanning
                      tint: Colors.of(QsWindow.window).primary },
            ChipTray {
                ChipButton {
                    symbol: "hard_drive"
                    label:  Translation.tr("Disks")
                    on:     root.section === "disks"
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: root.section = "disks"
                }
                ChipButton {
                    symbol: "inventory_2"
                    label:  Translation.tr("Packages")
                    on:     root.section === "packages"
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: root.section = "packages"
                }
            }
        ]

        // ══ A run in progress ═════════════════════════════════════════════════
        // Reclaim and uninstall share one runner (Storage._run), so whichever view you
        // are on when it starts or ends shows it. Success leaves on its own.
        Section {
            span:     3
            visible:  root.showLog
            glyph:    Storage.runBusy ? "󰑮" : Storage.runExit === 0 ? "󰄬" : "󰀦"
            title:    Storage.runLabel
            subtitle: Storage.runBusy ? "Running…" : Storage.runExit === 0 ? "Done" : "Failed"
            accent:   Storage.runBusy ? Colors.of(QsWindow.window).primary
                    : Storage.runExit === 0 ? Colors.of(QsWindow.window).success
                    : Colors.of(QsWindow.window).danger

            // Only on failure: on success the pane leaves on its own, and a button that
            // races a timer is a button that misses.
            actions: [
                BusyDot { running: Storage.runBusy; tint: Colors.of(QsWindow.window).primary },
                ChipTray {
                    visible: Storage.runDone && Storage.runExit !== 0
                    ChipButton {
                        symbol: "close"
                        label:  Translation.tr("Dismiss")
                        onActivated: root.returnToList()
                    }
                }
            ]

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 200

                Flickable {
                    id: logPane
                    anchors.fill: parent
                    contentHeight: logCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    onContentHeightChanged: if (Storage.runBusy)
                        logPane.contentY = Math.max(0, logPane.contentHeight - logPane.height)

                    ColumnLayout {
                        id: logCol
                        width: logPane.width
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: Storage.runLog
                            delegate: StyledText {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.text
                                variant: "caption"
                                // stderr is MUTED, not alarming: pacman and paccache report
                                // ordinary progress there. The exit code decides whether this
                                // went wrong, not the stream it arrived on.
                                emphasis: modelData.error ? "dim" : "normal"
                                font.family: Tokens.fontMono
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
                Scrollbar { flickable: logPane }
            }
        }

        // ══ Disks ═════════════════════════════════════════════════════════════
        // Each disk a capacity bar; the root disk's bar IS its breakdown (the free part
        // is its last segment), so "how full" and "full of what" are one picture.
        Section {
            span:     3
            visible:  root.section === "disks"
            glyph:    "󰋊"
            title:    Translation.tr("Disks")
            subtitle: Storage.filesystems.length + (Storage.filesystems.length === 1 ? " filesystem" : " filesystems")
            help:     Translation.tr("Each disk's used space against its size. The root disk is broken down by what fills it; Other is everything not measured on its own, and Reserved is the share the filesystem keeps for root — why the numbers seem not to add up.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingMd

            Repeater {
                model: Storage.filesystems
                delegate: DiskRow {
                    required property var modelData
                    disk: modelData
                }
            }
        }

        // ══ The space map ═════════════════════════════════════════════════════
        Section {
            span:     2
            visible:  root.section === "disks"
            glyph:    "󰉋"
            title:    Translation.tr("Home folder")
            subtitle: Storage.scanning ? "Scanning… " + Storage.scanElapsed + "s"
                    : Storage.hasScanned ? "The " + Storage.scanned.length + " biggest folders, by size"
                    : "Not scanned"
            help:     Translation.tr("Each tile is a folder in your home, as large as its share of the space. Hover one for its path. Nothing here is ever deleted for you.")
            accent:   Colors.of(QsWindow.window).primary

            actions: ChipTray {
                ChipButton {
                    symbol: Storage.scanning ? "close" : "search"
                    label:  Storage.scanning ? "Stop" : Storage.hasScanned ? "Rescan" : "Scan"
                    on:     !Storage.hasScanned && !Storage.scanning
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: Storage.scanning ? Storage.cancelScan() : Storage.scanHome()
                }
            }

            // Before the first scan: what the button is for.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                visible: !Storage.hasScanned
                spacing: Tokens.spacingSm

                Item { Layout.fillHeight: true }
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "folder_open"
                    variant: "display"
                    color: Colors.of(QsWindow.window).fgDim
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Storage.scanning ? "Measuring your folders…" : "Scan to see where your space went"
                    variant: "caption"
                    emphasis: "dim"
                }
                Item { Layout.fillHeight: true }
            }

            Item {
                id: map
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                visible: Storage.hasScanned

                readonly property var tiles: Treemap.layout(Storage.scanned.map(s => s.bytes), map.width, map.height)

                Repeater {
                    model: map.tiles
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property var folder: Storage.scanned[tile.modelData.index]
                        readonly property color hue: root.segmentColors[tile.modelData.index % root.segmentColors.length]
                        readonly property bool roomy: tile.width > 76 && tile.height > 40

                        // A gap of 2 between tiles: the map's grid, not a border on each.
                        x:      tile.modelData.x + 1
                        y:      tile.modelData.y + 1
                        width:  Math.max(0, tile.modelData.w - 2)
                        height: Math.max(0, tile.modelData.h - 2)
                        radius: Tokens.radiusSm
                        color:  Colors.of(QsWindow.window).alpha(tile.hue, tileHover.hovered ? 0.52 : 0.30)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        HoverHandler { id: tileHover }
                        HelpTip { text: tile.folder.path + " — " + Storage.bytes(tile.folder.bytes) }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingSm
                            visible: tile.width > 46 && tile.height > 22
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: tile.folder.label
                                variant: "caption"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: tile.roomy
                                text: Storage.bytes(tile.folder.bytes)
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                    }
                }
            }
        }

        // ══ Reclaim ═══════════════════════════════════════════════════════════
        Section {
            span:     1
            visible:  root.section === "disks"
            glyph:    "󰃢"
            title:    Translation.tr("Reclaim space")
            subtitle: Storage.probing ? "Measuring…"
                    : Storage.reclaimableBytes > 0 ? Storage.bytes(Storage.reclaimableBytes) + " to free"
                    : "Nothing to clean"
            help:     Translation.tr("Caches, old package versions and logs — files that rebuild themselves. Orphans are packages nothing needs any more; removing those uninstalls them, so it asks twice.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingXs

            // Directly above what it unlocks.
            PasswordField {
                helpText: "Unlocks the cleanups below."
            }

            Repeater {
                model: Storage.reclaimers
                delegate: ReclaimRow {
                    required property var modelData
                    rec: modelData
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingSm
                visible: Storage.reclaimers.length === 0 && !Storage.probing
                text: Translation.tr("The caches and logs are already small")
                variant: "caption"
                emphasis: "dim"
            }
        }

        // ══ Packages ══════════════════════════════════════════════════════════
        Section {
            span:     3
            visible:  root.section === "packages"
            glyph:    "󰏓"
            title:    Translation.tr("Installed on purpose")
            subtitle: root.pkgQuery !== ""
                      ? root.filteredPackages.length + " of " + root.sourcePackages.length
                      : root.sourcePackages.length + " packages"
            accent:   Colors.of(QsWindow.window).primary

            actions: ChipTray {
                ChipButton {
                    symbol: "refresh"
                    label:  Translation.tr("Rescan")
                    enabled: !Storage.packagesScanning
                    onActivated: Storage.scanPackages()
                }
            }

            // Where they came from — counts in the labels — and a search.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                TabStrip {
                    Layout.preferredWidth: 440
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "official", label: "Official " + root.officialPackages.length, icon: "package" },
                        { value: "aur",      label: "AUR " + root.aurPackages.length,           icon: "extension" },
                        { value: "flatpak",  label: "Flatpak " + root.flatpakPackages.length,   icon: "inventory_2" }
                    ]
                    current: root.pkgSource
                    onPicked: function (v) { root.pkgSource = v }
                }
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Search packages")
                    onEdited: function (t) { root.pkgQuery = t }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                PasswordField {
                    Layout.fillWidth: true
                    helpText: "Unlocks package removal."
                }

                // ── Bulk remove ────────────────────────────────────────────────
                // Same two-step "armed" idiom as every delete on this page. Selection is
                // global across the three sources — a mixed batch is fine,
                // Storage.uninstallPackages() splits it by source — so this stays correct
                // whichever source you are looking at when you press it.
                PanelButton {
                    capsule: true
                    visible: root.selectedIds.length > 0
                    variant: root.bulkArmed ? "primary" : "normal"
                    accent:  Colors.of(QsWindow.window).danger
                    readonly property bool blocked: root.selectionNeedsPassword && root.locked
                    glyph: blocked ? "󰌾" : "󰩺"
                    label: root.bulkArmed ? "Remove " + root.selectedIds.length + "?"
                         : blocked ? "Locked"
                         : "Remove selected (" + root.selectedIds.length + ")"
                    enabled: !Storage.runBusy && !blocked
                    Layout.alignment: Qt.AlignTop

                    onActivated: {
                        if (!root.bulkArmed) { root.bulkArmed = true; bulkDisarm.restart(); return }
                        root.bulkArmed = false
                        const ids = root.selectedIds
                        root.deselect(ids)
                        Storage.uninstallPackages(ids, root.sudoPass)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin:  Tokens.spacingSm
                Layout.rightMargin: Tokens.spacingSm
                Layout.bottomMargin: Tokens.spacingXs
                spacing: Tokens.spacingMd

                Rectangle {
                    Layout.preferredWidth: root.pkgCheckboxW
                    Layout.alignment: Qt.AlignVCenter
                    width: 16; height: 16
                    radius: Tokens.radiusXs
                    color: root.allFilteredSelected ? Colors.of(QsWindow.window).primary : "transparent"
                    border.width: Tokens.borderWidth
                    border.color: root.allFilteredSelected ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).outline

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: root.allFilteredSelected
                        glyph: "󰄬"
                        variant: "micro"
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }

                    TapHandler { onTapped: root.toggleSelectAllFiltered() }
                }

                // The name takes all the slack, in the header AND every row, so the
                // fixed columns after it sit at the same x down the whole list.
                StyledText {
                    Layout.fillWidth: true
                    text: "Package"; variant: "caption"; emphasis: "muted"
                }
                StyledText { Layout.preferredWidth: root.pkgVersionW; text: "Version"; variant: "caption"; emphasis: "muted" }
                StyledText {
                    Layout.preferredWidth: root.pkgSizeW
                    horizontalAlignment: Text.AlignRight
                    text: "Size"; variant: "caption"; emphasis: "muted"
                }
                Item { Layout.preferredWidth: root.pkgActionW; Layout.minimumWidth: root.pkgActionW }
            }
            Divider { Layout.leftMargin: Tokens.spacingSm; Layout.rightMargin: Tokens.spacingSm }

            Repeater {
                model: root.filteredPackages
                delegate: Item {
                    id: pkgRow
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: pkgRowContent.implicitHeight + Tokens.spacingXs * 2

                    // Flatpak needs no sudo — it authenticates through
                    // polkit — so a flatpak row is never "Locked" the way
                    // a pacman one is. See Storage.uninstallPackages().
                    readonly property bool blocked:
                        pkgRow.modelData.source !== "flatpak" && root.locked

                    ArmLatch {
                        id: pkgDeleteLatch
                        onConfirmed: {
                            root.deselect([pkgRow.modelData.id])
                            Storage.uninstallPackages([pkgRow.modelData.id], root.sudoPass)
                        }
                    }

                    RowLayout {
                        id: pkgRowContent
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.leftMargin:  Tokens.spacingSm
                        anchors.rightMargin: Tokens.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingMd

                        Rectangle {
                            Layout.preferredWidth: root.pkgCheckboxW
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16
                            radius: Tokens.radiusXs
                            color: root.isSelected(pkgRow.modelData.id) ? Colors.of(QsWindow.window).primary : "transparent"
                            border.width: Tokens.borderWidth
                            border.color: root.isSelected(pkgRow.modelData.id)
                                ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).outline

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: root.isSelected(pkgRow.modelData.id)
                                glyph: "󰄬"
                                variant: "micro"
                                color: Colors.of(QsWindow.window).fgOnPrimary
                            }

                            TapHandler { onTapped: root.toggleSelect(pkgRow.modelData.id) }
                        }

                        // ── Name, with the description on hover ───────
                        // Hover target and tooltip anchor are the name
                        // text itself now, not the whole row — so
                        // hovering the Remove button doesn't pop a
                        // description, and the tooltip lands directly
                        // under the name rather than under the row's
                        // trailing edge (wherever that happened to be).
                        StyledText {
                            id: pkgNameText
                            Layout.fillWidth: true
                            text: pkgRow.modelData.name
                            variant: "body"
                            elide: Text.ElideRight

                            // What it is — the card's shared tip, like
                            // every other explanation in Settings.
                            HelpTip { text: pkgRow.modelData.description }
                        }

                        StyledText {
                            Layout.preferredWidth: root.pkgVersionW
                            text: pkgRow.modelData.version
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.preferredWidth: root.pkgSizeW
                            horizontalAlignment: Text.AlignRight
                            text: Storage.bytes(pkgRow.modelData.bytes)
                            variant: "caption"
                            color: Colors.of(QsWindow.window).fgMuted
                        }

                        // Same two-step "armed" idiom as the reclaimers above —
                        // this deletes a package outright, so it earns the same
                        // confirm every risky button on this page gets. Ghost
                        // rather than normal/bordered by default: a bordered
                        // button per row is exactly the extra chrome a flat list
                        // is trying to avoid — it only needs to be loud once armed.
                        PanelButton {
                            capsule: true
                            Layout.preferredWidth: root.pkgActionW
                            Layout.minimumWidth: root.pkgActionW
                            Layout.maximumWidth: root.pkgActionW
                            Layout.alignment: Qt.AlignVCenter
                            variant: pkgDeleteLatch.armed ? "primary" : "ghost"
                            accent:  Colors.of(QsWindow.window).danger
                            glyph: pkgRow.blocked ? "󰌾" : "󰩺"
                            label: pkgDeleteLatch.armed ? "Remove?"
                                 : pkgRow.blocked ? "Locked" : "Remove"
                            enabled: !Storage.runBusy && !pkgRow.blocked

                            onActivated: pkgDeleteLatch.trigger()
                        }
                    }

                    Divider {
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.bottom: parent.bottom
                    }
                }
            }

            // ── Empty states ──────────────────────────────────────────
            Surface {
                Layout.fillWidth: true
                visible: Storage.packagesScanning && !Storage.hasScannedPackages
                elevation: Tokens.elevationNested
                implicitHeight: scanBox.implicitHeight + Tokens.spacingLg * 2

                RowLayout {
                    id: scanBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    BusyDot { running: true }
                    StyledText {
                        text: Translation.tr("Scanning installed packages…")
                        variant: "body"
                        emphasis: "dim"
                    }
                }
            }

            Surface {
                Layout.fillWidth: true
                visible: Storage.hasScannedPackages
                    && root.filteredPackages.length === 0
                    && !Storage.packagesScanning
                elevation: Tokens.elevationNested
                implicitHeight: pkgEmptyBox.implicitHeight + Tokens.spacingLg * 2

                ColumnLayout {
                    id: pkgEmptyBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs

                    StyledText {
                        text: root.pkgQuery !== ""
                            ? "Nothing matches “" + root.pkgQuery + "”."
                            : root.pkgSource === "aur"
                                ? "No AUR packages installed."
                            : root.pkgSource === "flatpak"
                                ? "No Flatpak apps installed."
                                : "No official packages installed explicitly."
                        variant: "body"
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // ── PasswordField ─────────────────────────────────────────────────────────
    // Shared by the Reclaim column (Disks) and the Packages toolbar — "directly
    // above what it unlocks" applies twice now, since both tabs gate a delete
    // action on sudo. The two instances share one value (root.sudoPass) through
    // an explicit, guarded sync rather than a plain `text: root.sudoPass`
    // binding — QML silently breaks that binding the moment a user types into
    // the field, which would leave only whichever field was typed into last
    // actually driving `root.locked`.
    // ── DiskRow — one filesystem as a capacity bar ────────────────────────────
    // The root disk's bar is its composition (Storage.rootComposition, whose last
    // segments are Reserved and Free), with a legend; every other disk is used/free.
    // Proportional by construction: a Row of explicit widths, never a RowLayout, which
    // would hand leftover space out and distort the proportions that are the point.
    component DiskRow: ColumnLayout {
        id: dr
        property var disk: ({})
        readonly property bool isRoot: dr.disk.mount === "/" && Storage.rootComposition.length > 0
        // Generous thresholds on purpose — a 25%-full disk is not a problem, and
        // colouring it like one teaches you to ignore the colour.
        readonly property color tint: dr.disk.fraction > 0.9  ? Colors.of(QsWindow.window).danger
                                    : dr.disk.fraction > 0.75 ? Colors.of(QsWindow.window).warning
                                    : Colors.of(QsWindow.window).primary
        readonly property var segs: dr.isRoot
            ? Storage.rootComposition.filter(s => s.bytes > 0)
            : [{ kind: "used", label: "Used", bytes: dr.disk.used },
               { kind: "free", label: "Free", bytes: dr.disk.avail }]
        readonly property real total: dr.segs.reduce((t, s) => t + s.bytes, 0)

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            StyledText {
                text: dr.disk.mount
                variant: "body"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: dr.disk.fstype + (dr.disk.rotational ? " · spinning disk" : " · SSD")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            StyledText {
                text: Storage.bytes(dr.disk.avail) + " free"
                variant: "body"
                font.weight: Font.Medium
                color: dr.disk.fraction > 0.75 ? dr.tint : Colors.of(QsWindow.window).fg
            }
            StyledText {
                text: "of " + Storage.bytes(dr.disk.size)
                variant: "caption"
                emphasis: "dim"
            }
        }

        Row {
            id: bar
            Layout.fillWidth: true
            Layout.preferredHeight: dr.isRoot ? 14 : 8
            spacing: 2
            readonly property real usable: Math.max(0, bar.width - bar.spacing * Math.max(0, dr.segs.length - 1))

            Repeater {
                model: dr.segs
                delegate: Rectangle {
                    id: seg
                    required property var modelData
                    required property int index
                    // Floored at 3px so a slice that's real but tiny still shows.
                    width: Math.max(3, dr.total > 0 ? (seg.modelData.bytes / dr.total) * bar.usable : 0)
                    height: bar.height
                    radius: Tokens.radiusXs
                    color: dr.isRoot ? root.segmentColor(seg.modelData.kind, seg.index)
                         : seg.modelData.kind === "used" ? dr.tint
                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                    Behavior on width { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.travel } }
                }
            }
        }

        // The root disk's legend. A Flow: the segment count follows what's installed.
        Flow {
            Layout.fillWidth: true
            visible: dr.isRoot
            spacing: Tokens.spacingLg

            Repeater {
                model: dr.isRoot ? dr.segs : []
                delegate: Row {
                    id: leg
                    required property var modelData
                    required property int index
                    spacing: Tokens.spacingSm
                    Rectangle {
                        width: 8; height: 8
                        radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.segmentColor(leg.modelData.kind, leg.index)
                    }
                    StyledText {
                        text: leg.modelData.label
                        variant: "caption"
                        emphasis: "dim"
                    }
                    StyledText {
                        text: Storage.bytes(leg.modelData.bytes)
                        variant: "caption"
                    }
                }
            }
        }
    }

    // ── ReclaimRow — one cleanup: what, how much, and the button ──────────────
    component ReclaimRow: Item {
        id: rr
        property var rec: ({})
        readonly property bool blocked: Storage.needsPassword(rr.rec.id) && root.locked
        readonly property var ctx: Storage.contextFor(rr.rec.id)

        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: rrCol.implicitHeight + Tokens.spacingSm * 2

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: rrHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05) : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
        HoverHandler { id: rrHover }
        // What it removes, and how much of its folder that is — the explanation that
        // was two lines under every row.
        HelpTip {
            text: rr.rec.detail + (rr.ctx
                ? (rr.rec.known ? " — " + Storage.bytes(rr.rec.bytes) + " of the " + Storage.bytes(rr.ctx.bytes) + " in " + rr.ctx.path
                                : " — " + rr.ctx.path + " is " + Storage.bytes(rr.ctx.bytes) + " in total")
                : "")
        }

        ColumnLayout {
            id: rrCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacingSm
            anchors.rightMargin: Tokens.spacingXs
            spacing: Tokens.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    text: rr.rec.label
                    variant: "body"
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    text: rr.rec.known ? Storage.bytes(rr.rec.bytes) : "unknown"
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: rr.rec.known && rr.rec.bytes > 0 ? Colors.of(QsWindow.window).success
                                                            : Colors.of(QsWindow.window).fgDim
                }

                // Two-step only where it's earned: orphan removal UNINSTALLS packages,
                // and "installed as a dependency" is not "unwanted". The others delete
                // files that come back on their own; confirming all of them would train
                // the reflex that dismisses the one that matters.
                PanelButton {
                    capsule: true
                    id: cleanBtn
                    readonly property bool risky: rr.rec.id === "orphans"
                    ArmLatch {
                        id: cleanLatch
                        armWhen: cleanBtn.risky
                        onConfirmed: Storage.reclaim(rr.rec.id, root.sudoPass)
                    }
                    variant: cleanLatch.armed ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).danger
                    // Icon AND label, never colour alone.
                    glyph: rr.blocked ? "󰌾" : "󰩺"
                    label: cleanLatch.armed ? "Remove them?" : rr.blocked ? "Locked" : "Clean"
                    enabled: !Storage.runBusy && !rr.blocked && (!rr.rec.known || rr.rec.bytes > 0)
                    onActivated: cleanLatch.trigger()
                }
            }

            // Share of the biggest reclaimer: which one is most of the win.
            Meter {
                Layout.fillWidth: true
                visible: rr.rec.known && Storage.largestReclaim > 0
                value:  Storage.largestReclaim > 0 ? rr.rec.bytes / Storage.largestReclaim : 0
                accent: Colors.of(QsWindow.window).success
            }
        }
    }

    component PasswordField: ColumnLayout {
        id: pwField
        property string helpText: ""

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs

        // The shared field, not a hand-built Surface + TextInput. Both copies (Disks
        // and Packages) drive and follow root.sudoPass: `seed` refills a field while it
        // isn't being typed in, `edited` writes every keystroke back.
        InputField {
            cornerRadius: implicitHeight / 2
            Layout.fillWidth: true
            secret: true
            icon: root.locked ? "lock" : "lock_open"
            placeholder: Translation.tr("sudo password")
            seed: root.sudoPass
            onEdited: function (v) { if (v !== root.sudoPass) root.sudoPass = v }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: root.locked
                ? pwField.helpText
                : "Unlocked — it goes straight to sudo and isn't stored."
            variant: "caption"
            color: root.locked ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).success
            wrapMode: Text.WordWrap
        }
    }
}
