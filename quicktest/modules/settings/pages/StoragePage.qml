pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── StoragePage ───────────────────────────────────────────────────────────────
// What's using the disks, and what can be given back.
//
// ── Shape: gauges, two columns, a strip ───────────────────────────────────────
// The same skeleton as NetworkPage, because it answers the same kind of question and
// should not look like a different application:
//
//     ┌ disks — one RadialGauge per filesystem, across the top ────────────┐
//     ├ reclaim space              │ your home folder ────────────────────┤
//     └ what's on / — stacked composition bar + legend ───────────────────┘
//
// The first version was a wall of left-aligned text with a number on the right, which
// read as a table rather than as a page of this shell. The gauges are AboutPage's
// GaugeTile idiom, the foot strip is NetworkPage's traffic strip idiom, and both were
// already the established way to say "here is a proportion" here.
//
// ── The composition strip is the one genuinely new picture ────────────────────
// Everything else on this page says how big something is. The strip says what the disk is
// made OF — /usr against the package cache against free space — which is the question
// behind "why is my disk full" and which no single row could answer.
//
// ── Trash and app caches are reported, not offered ────────────────────────────
// They appear in the home column, with paths, and get no button. See Storage.qml.
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

    readonly property bool locked: passField.text.length === 0

    // Segment colours for the composition strip. Cycled by index so adjacent slices stay
    // distinguishable; "Other" and "Free" are deliberately NOT in the cycle, because they
    // aren't things — they're the remainder and the gap.
    readonly property var segmentColors: [
        Colors.focus, Colors.info, Colors.warning, Colors.ramp5, Colors.success
    ]

    function segmentColor(kind, index) {
        if (kind === "free")     return Colors.alpha(Colors.fg, 0.10)
        if (kind === "reserved") return Colors.alpha(Colors.fg, 0.18)
        if (kind === "other")    return Colors.alpha(Colors.fg, 0.28)
        return root.segmentColors[index % root.segmentColors.length]
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        // ══ Disks ═════════════════════════════════════════════════════════════
        StyledText { text: "Disks"; variant: "label"; emphasis: "muted" }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingLg

            Repeater {
                model: Storage.filesystems
                delegate: Surface {
                    id: diskCard
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 148
                    elevation: Tokens.elevationNested

                    // Generous thresholds on purpose — a 25%-full disk is not a problem,
                    // and colouring it like one teaches you to ignore the colour.
                    readonly property color tint: diskCard.modelData.fraction > 0.9 ? Colors.danger
                                                : diskCard.modelData.fraction > 0.75 ? Colors.warning
                                                : Colors.success

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingLg

                        RadialGauge {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth:  100
                            implicitHeight: 100
                            thickness: 9
                            value:  diskCard.modelData.fraction
                            accent: diskCard.tint

                            // The hole carries FREE space, not percent-used. "How much room
                            // have I got" is the question people open this page with, and a
                            // percentage makes you do arithmetic to answer it. The ring
                            // already shows the proportion.
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: -2

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Storage.bytes(diskCard.modelData.avail).split(" ")[0]
                                    variant: "display"
                                    font.weight: Font.Bold
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Storage.bytes(diskCard.modelData.avail).split(" ")[1]
                                        + " free"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingXs

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm
                                StyledText {
                                    text: "󰋊"
                                    color: diskCard.tint
                                    variant: "body"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: diskCard.modelData.mount
                                    variant: "title"
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Storage.bytes(diskCard.modelData.used) + " used of "
                                    + Storage.bytes(diskCard.modelData.size)
                                variant: "caption"
                                emphasis: "dim"
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: diskCard.modelData.fstype
                                    + (diskCard.modelData.rotational ? " · spinning disk" : " · SSD")
                                variant: "caption"
                                color: Colors.fgDim
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ══ Middle: reclaim | home ════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.spacingXl

                opacity: root.showLog ? 0.0 : 1.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                // ── Reclaim ───────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd

                        StyledText { text: "Reclaim space"; variant: "label"; emphasis: "muted" }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            visible: Storage.reclaimableBytes > 0
                            text: Storage.bytes(Storage.reclaimableBytes) + " available"
                            variant: "caption"
                            color: Colors.success
                        }
                        BusyDot { running: Storage.probing }
                    }

                    // ── Password, directly above what it unlocks ──────────────
                    // It was at the foot of the rail in an earlier cut — ~800px from the
                    // buttons it gates, so they all read as permanently dead with the
                    // explanation off the bottom of the screen.
                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: passBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: passBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingSm

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd

                                StyledText {
                                    text: root.locked ? "󰌾" : "󰌿"
                                    color: root.locked ? Colors.fgMuted : Colors.success
                                    variant: "body"
                                }

                                TextInput {
                                    id: passField
                                    Layout.fillWidth: true
                                    echoMode: TextInput.Password
                                    color: Colors.fg
                                    selectionColor: Colors.alpha(Colors.focus, 0.35)
                                    selectByMouse: true
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontBody
                                    verticalAlignment: TextInput.AlignVCenter

                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: passField.text.length === 0
                                        text: "sudo password…"
                                        variant: "body"
                                        emphasis: "dim"
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.locked
                                    ? "Enter your password to unlock the cleanups below."
                                    : "Unlocked. Your password goes straight to sudo and isn't stored."
                                variant: "caption"
                                emphasis: "dim"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Plain Item around the Flickable, NOT a bare Flickable ─
                    // Scrollbar reparents itself to `flickable.parent` and anchors across
                    // it. If that parent is a Layout, it gets anchored AND laid out at the
                    // same time — which is the "anchors on an item managed by a layout"
                    // warning, repeated every frame. The wrapper gives it a plain Item to
                    // live in. Same reason NetworkPage and the first cut of this page wrap
                    // theirs.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            id: recPane
                            anchors.fill: parent
                            contentHeight: recCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: recCol
                                width: recPane.width
                                spacing: Tokens.spacingMd

                                Repeater {
                                    model: Storage.reclaimers
                                    delegate: Surface {
                                        id: rec
                                        required property var modelData

                                        Layout.fillWidth: true
                                        elevation: Tokens.elevationNested
                                        implicitHeight: recBox.implicitHeight + Tokens.spacingLg * 2

                                        readonly property bool blocked: Storage.needsPassword(rec.modelData.id)
                                                                     && root.locked
                                        readonly property var ctx: Storage.contextFor(rec.modelData.id)

                                        ColumnLayout {
                                            id: recBox
                                            anchors.left:  parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.margins: Tokens.spacingLg
                                            spacing: Tokens.spacingSm

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Tokens.spacingMd

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: rec.modelData.label
                                                    variant: "body"
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    text: rec.modelData.known
                                                        ? Storage.bytes(rec.modelData.bytes)
                                                        : "unknown"
                                                    variant: "body"
                                                    color: rec.modelData.known ? Colors.success
                                                                               : Colors.fgDim
                                                }

                                                // ── Two-step, but only where it's earned ──
                                                // Five of these delete files that come back on
                                                // their own. Orphan removal UNINSTALLS
                                                // packages, and "installed as a dependency" is
                                                // not "unwanted" — a CLI tool something else
                                                // pulled in, that you then use directly, looks
                                                // identical to cruft from here. Confirming all
                                                // six would train the reflex that dismisses the
                                                // one that matters.
                                                PanelButton {
                                                    id: cleanBtn
                                                    Layout.alignment: Qt.AlignVCenter
                                                    readonly property bool risky: rec.modelData.id === "orphans"
                                                    property bool armed: false

                                                    variant: cleanBtn.armed ? "primary" : "normal"
                                                    accent:  Colors.danger
                                                    // Icon AND label, never colour alone:
                                                    // `danger` shares a hue with `primary` here.
                                                    glyph: rec.blocked ? "󰌾" : "󰩺"
                                                    label: cleanBtn.armed ? "Remove them?"
                                                         : rec.blocked ? "Locked" : "Clean"
                                                    enabled: !Storage.runBusy && !rec.blocked

                                                    onActivated: {
                                                        if (cleanBtn.risky && !cleanBtn.armed) {
                                                            cleanBtn.armed = true
                                                            return
                                                        }
                                                        cleanBtn.armed = false
                                                        Storage.reclaim(rec.modelData.id, passField.text)
                                                    }

                                                    Timer {
                                                        running: cleanBtn.armed
                                                        interval: 4000
                                                        onTriggered: cleanBtn.armed = false
                                                    }
                                                }
                                            }

                                            // Share of the biggest reclaimer, so it reads at a
                                            // glance which one is most of the win.
                                            Meter {
                                                Layout.fillWidth: true
                                                visible: rec.modelData.known && Storage.largestReclaim > 0
                                                value:  Storage.largestReclaim > 0
                                                      ? rec.modelData.bytes / Storage.largestReclaim : 0
                                                accent: Colors.success
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: rec.modelData.detail
                                                variant: "caption"
                                                emphasis: "dim"
                                                wrapMode: Text.WordWrap
                                            }

                                            // Replaces the old duplicate "largest folders"
                                            // section: how much of the containing directory is
                                            // actually stale. When the size is unknown, the
                                            // containing total is the only number there is and
                                            // therefore worth more, not less.
                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: rec.ctx !== null
                                                text: !rec.ctx ? ""
                                                    : rec.modelData.known
                                                    ? Storage.bytes(rec.modelData.bytes) + " of the "
                                                      + Storage.bytes(rec.ctx.bytes) + " in " + rec.ctx.path
                                                    : rec.ctx.path + " is "
                                                      + Storage.bytes(rec.ctx.bytes) + " in total"
                                                variant: "caption"
                                                color: Colors.fgDim
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                Surface {
                                    Layout.fillWidth: true
                                    visible: Storage.reclaimers.length === 0 && !Storage.probing
                                    elevation: Tokens.elevationNested
                                    implicitHeight: emptyBox.implicitHeight + Tokens.spacingLg * 2

                                    ColumnLayout {
                                        id: emptyBox
                                        anchors.left:  parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Tokens.spacingLg
                                        spacing: Tokens.spacingXs

                                        RowLayout {
                                            spacing: Tokens.spacingMd
                                            StyledText { text: "󰄬"; color: Colors.success; variant: "body" }
                                            StyledText {
                                                text: "Nothing to clean"
                                                variant: "body"
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: "The caches and logs are already small. They'll "
                                                + "build up again as you install things."
                                            variant: "caption"
                                            emphasis: "dim"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        Scrollbar { flickable: recPane }
                    }
                }

                // ── Home ──────────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd

                        StyledText { text: "Your home folder"; variant: "label"; emphasis: "muted" }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            visible: Storage.scanning
                            text: Storage.scanElapsed + "s"
                            variant: "caption"
                            emphasis: "dim"
                        }
                        BusyDot { running: Storage.scanning }
                        PanelButton {
                            variant: "normal"
                            glyph: Storage.scanning ? "󰅖" : "󰍉"
                            label: Storage.scanning ? "Stop"
                                 : Storage.hasScanned ? "Rescan" : "Scan"
                            onActivated: Storage.scanning ? Storage.cancelScan() : Storage.scanHome()
                        }
                    }

                    // Empty state that says what the button is FOR, rather than a bare
                    // "not measured yet".
                    Surface {
                        Layout.fillWidth: true
                        visible: !Storage.hasScanned
                        elevation: Tokens.elevationNested
                        implicitHeight: homeIntroBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: homeIntroBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingXs

                            RowLayout {
                                spacing: Tokens.spacingMd
                                StyledText { text: "󰒃"; color: Colors.info; variant: "body" }
                                StyledText {
                                    text: "Your files are off limits"
                                    variant: "body"
                                    font.weight: Font.DemiBold
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Scanning shows where your space went — Trash, app "
                                    + "caches, games. Nothing here is ever deleted for you; "
                                    + "the cleanups above only touch files that rebuild "
                                    + "themselves."
                                variant: "caption"
                                emphasis: "dim"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            id: homePane
                            anchors.fill: parent
                            contentHeight: homeCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: homeCol
                                width: homePane.width
                                spacing: Tokens.spacingSm

                                Repeater {
                                    model: Storage.scanned
                                    delegate: Item {
                                        id: fr
                                        required property var modelData

                                        Layout.fillWidth: true
                                        implicitHeight: frCol.implicitHeight

                                        // Share of the LARGEST folder, not of the total. One
                                        // folder here is 537 GB of a 750 GB home, so shares of
                                        // the total would render every other bar as an
                                        // invisible sliver.
                                        readonly property real share: Storage.scanned.length > 0
                                            && Storage.scanned[0].bytes > 0
                                            ? fr.modelData.bytes / Storage.scanned[0].bytes : 0

                                        ColumnLayout {
                                            id: frCol
                                            width: fr.width
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Tokens.spacingMd

                                                StyledText {
                                                    text: fr.modelData.label
                                                    variant: "body"
                                                    elide: Text.ElideRight
                                                    Layout.maximumWidth: 200
                                                }
                                                Item { Layout.fillWidth: true }
                                                StyledText {
                                                    text: Storage.bytes(fr.modelData.bytes)
                                                    variant: "caption"
                                                    color: Colors.fgMuted
                                                }
                                            }

                                            Meter {
                                                Layout.fillWidth: true
                                                value:  fr.share
                                                accent: Colors.info
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Scrollbar { flickable: homePane }
                    }
                }
            }

            // ── The run log ───────────────────────────────────────────────────
            Flickable {
                id: logPane
                anchors.fill: parent
                contentHeight: logCol.implicitHeight
                clip: true
                interactive: root.showLog

                opacity: root.showLog ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                onContentHeightChanged: if (Storage.runBusy)
                    logPane.contentY = Math.max(0, logPane.contentHeight - logPane.height)

                ColumnLayout {
                    id: logCol
                    width: logPane.width
                    spacing: Tokens.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Tokens.spacingSm
                        spacing: Tokens.spacingMd

                        BusyDot { running: Storage.runBusy }
                        StyledText {
                            Layout.fillWidth: true
                            text: Storage.runBusy ? Storage.runLabel + "…"
                                : Storage.runExit === 0 ? Storage.runLabel + " — done"
                                : Storage.runLabel + " — failed"
                            variant: "body"
                            font.weight: Font.DemiBold
                            color: Storage.runBusy ? Colors.fg
                                 : Storage.runExit === 0 ? Colors.success : Colors.danger
                        }
                        // Only on failure: on success the pane leaves on its own, and a
                        // button that races a timer is a button that misses.
                        PanelButton {
                            visible: Storage.runDone && Storage.runExit !== 0
                            variant: "ghost"
                            label: "Dismiss"
                            onActivated: root.returnToList()
                        }
                    }

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

        // ══ Foot: what the root filesystem is made of ═════════════════════════
        // NetworkPage puts a full-width strip under its columns for the same reason: the
        // columns are top-heavy, and the band underneath is where a wide picture belongs.
        Surface {
            Layout.fillWidth: true
            visible: Storage.rootComposition.length > 0
            elevation: Tokens.elevationNested
            implicitHeight: compBox.implicitHeight + Tokens.spacingLg * 2

            ColumnLayout {
                id: compBox
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    StyledText { text: "What's on /"; variant: "label"; emphasis: "muted" }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        // Both remainders explained in place. "Other" is what the measured
                        // directories don't account for; "Reserved" is the 5% ext4 keeps
                        // for root, and is the reason the numbers appear not to add up.
                        text: "“Other” is everything not measured individually · "
                            + "“Reserved” is kept by the filesystem for root"
                        variant: "caption"
                        color: Colors.fgDim
                        elide: Text.ElideRight
                    }
                }

                // ── The bar ───────────────────────────────────────────────────
                // Segments with a small gap rather than one clipped rounded bar: Qt's
                // `clip` is rectangular, so a rounded container would square off the ends
                // of the fill anyway. The gaps read as deliberate and avoid the problem.
                // A plain Row with explicit widths, NOT a RowLayout. A RowLayout
                // redistributes leftover space among fillWidth items, which would quietly
                // distort the proportions — and being proportional is the entire job of
                // this bar. Widths are computed against the space left after the gaps, so
                // the segments always sum to the full width.
                Row {
                    id: bar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    spacing: 2

                    readonly property var segs: Storage.rootComposition.filter(s => s.bytes > 0)
                    readonly property real total: {
                        let t = 0
                        for (const s of bar.segs) t += s.bytes
                        return t
                    }
                    // Space actually available to the coloured blocks.
                    readonly property real usable: Math.max(0,
                        bar.width - bar.spacing * Math.max(0, bar.segs.length - 1))

                    Repeater {
                        model: bar.segs
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            required property int index

                            // Floored at 3px so a slice that's real but tiny (/var/log is
                            // 197 MB of 107 GB — 0.2%, which rounds to nothing) still shows
                            // rather than reading as absent.
                            width: Math.max(3, bar.total > 0
                                ? (seg.modelData.bytes / bar.total) * bar.usable : 0)
                            height: bar.height
                            radius: Tokens.radiusXs
                            color:  root.segmentColor(seg.modelData.kind, seg.index)
                        }
                    }
                }

                // ── Legend ────────────────────────────────────────────────────
                // A Flow, not a Row: the segment count varies with what's installed, and a
                // Row would push the last entries off the edge on a narrower page.
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingLg

                    Repeater {
                        model: Storage.rootComposition
                        delegate: Row {
                            id: leg
                            required property var modelData
                            required property int index
                            spacing: Tokens.spacingSm
                            visible: leg.modelData.bytes > 0

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
        }
    }
}
