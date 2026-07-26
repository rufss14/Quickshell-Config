pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services"
import ".."

// ── AboutPage ─────────────────────────────────────────────────────────────────
// What this machine is, and what it's doing right now. Queried live, never hardcoded.
//
// One script (scripts/specs.sh) for the static facts rather than a Process per field.
// It emits KEY=value lines, which is the cheapest thing to parse that isn't ambiguous.
// Live load comes from the SysInfo service (/proc via FileView, no subprocess), and
// displays come from Hypr — the shell is already subscribed to Hyprland's monitor list,
// so asking a shell script the same question would be a second source of truth that
// goes stale the moment a screen is unplugged.
//
// ── On the charts ─────────────────────────────────────────────────────────────
// Three deliberate calls, each against the obvious instinct:
//
//   · CPU and memory are METERS and a sparkline, not ring gauges. A radial gauge for
//     one ratio is a two-slice pie — it asks the eye to compare arcs where a bar lets
//     it compare positions.
//   · The twelve per-core bars are ONE hue, not twelve. Their length is the value;
//     colouring them by that same value would spend the only free channel restating
//     what the bars already say. Cores are nominal — core 7 isn't "more" than core 3 —
//     so a ramp across them would be meaningless besides.
//   · Every number here wears a TEXT colour, not the accent. The mark beside it
//     carries the identity; the figure is text and reads as text.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var spec: ({})

    // Live sampling runs only while this page exists. The card's Loader destroys it
    // when you flip to another page, which is what stops the timer.
    Component.onCompleted:   SysInfo.acquire()
    Component.onDestruction: SysInfo.release()

    Process {
        id: specsQuery
        running: true
        command: ["bash", Quickshell.env("HOME") + "/.config/quicktest/scripts/specs.sh"]

        stdout: StdioCollector {
            onStreamFinished: {
                const next = {}
                for (const line of text.split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq < 0) continue
                    next[line.substring(0, eq)] = line.substring(eq + 1)
                }
                // Replaced, not mutated in place: mutating wouldn't fire the change
                // signal and every row below would keep showing the em-dash.
                root.spec = next
            }
        }
    }

    function fact(key) { return root.spec[key] ? root.spec[key] : "—" }

    Flickable {

        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: page.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: page
            width: parent.width
            spacing: Tokens.spacingLg

            PanelHeader {
                glyph:     "󰋼"
                title:     "About"
                titleTail: root.spec.HOST ? root.spec.HOST : ""
                subtitle:  root.fact("DISTRO")

                PanelButton {
                    label: "Refresh"
                    glyph: "󰑐"
                    onActivated: {
                        specsQuery.running = false
                        specsQuery.running = true
                    }
                }
            }

            Divider {}

            // ══ Hero ══════════════════════════════════════════════════════════
            // The distro logo at size, the hostname as the hero figure. The logo path
            // comes from os-release's LOGO= via specs.sh, so this is whatever distro
            // you're on rather than a hardcoded Arch asset.
            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: heroRow.implicitHeight + Tokens.spacingXxl * 2

                RowLayout {
                    id: heroRow
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin:  Tokens.spacingXxl
                    anchors.rightMargin: Tokens.spacingXxl
                    spacing: Tokens.spacingXxl

                    // Loader-gated: an Image with an empty source resolves to
                    // Quickshell's qs-blackhole placeholder and warns. A distro with no
                    // LOGO= in os-release should show nothing, not a broken icon.
                    Loader {
                        active: String(root.spec.LOGO ?? "") !== ""
                        Layout.alignment: Qt.AlignVCenter

                        sourceComponent: Image {
                            source: "file://" + root.spec.LOGO
                            // sourceSize forces the SVG to rasterise AT this size
                            // rather than at its intrinsic one and scale up — the
                            // difference between a crisp logo and a blurry one.
                            sourceSize: Qt.size(96, 96)
                            width:  96
                            height: 96
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        // The hero figure: same sans as everything else, proportional
                        // figures. tabular-nums on a large standalone value makes it
                        // look loose, and a display face would read as decoration.
                        StyledText {
                            Layout.fillWidth: true
                            text:    root.spec.HOST ? root.spec.HOST : "—"
                            variant: "display"
                            font.weight: Font.Bold
                            elide:   Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            rich: true
                            text: "<b>" + root.fact("DISTRO") + "</b>  ·  " + root.fact("KERNEL")
                            variant:  "body"
                            emphasis: "muted"
                            elide:    Text.ElideRight
                        }
                        StyledText {
                            Layout.topMargin: Tokens.spacingSm
                            rich: true
                            text: "Up <b>" + root.fact("UPTIME") + "</b>"
                            variant:  "caption"
                            emphasis: "dim"
                        }
                    }
                }
            }

            // ══ Live ══════════════════════════════════════════════════════════
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Right now"
                variant: "label"
                emphasis: "muted"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingXl

                // ── CPU ───────────────────────────────────────────────────────
                Surface {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    elevation: Tokens.elevationNested
                    implicitHeight: cpuBox.implicitHeight + Tokens.spacingXl * 2

                    ColumnLayout {
                        id: cpuBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        anchors.margins: Tokens.spacingXl
                        spacing: Tokens.spacingMd

                        StyledText {
                            text: "Processor"
                            variant: "body"
                            font.weight: Font.DemiBold
                        }

                        GaugeTile {
                            Layout.fillWidth: true
                            value:   SysInfo.cpu
                            history: SysInfo.history
                            temp:    SysInfo.cpuTemp
                            caption: SysInfo.cores.length + " threads"
                        }

                        Divider { Layout.topMargin: Tokens.spacingXs }

                        StyledText {
                            Layout.topMargin: Tokens.spacingXs
                            text: "Per thread"
                            variant:  "caption"
                            emphasis: "dim"
                        }

                        // ── Per-core ──────────────────────────────────────────
                        // One hue for every bar. Length is the value; a darker-is-busier
                        // ramp would encode it twice and say nothing new. Cores are
                        // nominal anyway — core 7 isn't "more" than core 3.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            // 2px of surface between neighbours, rather than a border
                            // drawn around each bar to separate it.
                            spacing: 2

                            Repeater {
                                model: SysInfo.cores.length

                                Item {
                                    id: core
                                    required property int index

                                    readonly property real load: SysInfo.cores[core.index] ?? 0

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color:  Colors.alpha(Colors.fg, 0.08)
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width:  parent.width
                                        // A floor of 2px so an idle core is still a mark
                                        // rather than a gap — twelve bars with three
                                        // missing reads as broken, not as idle.
                                        height: Math.max(2, parent.height * core.load)
                                        radius: 2
                                        color:  Colors.focus

                                        // ── Tracking, not ticking ─────────────
                                        // This WAS Motion.standard + OutCubic, which is
                                        // the right recipe for a discrete change and the
                                        // wrong one here: sampled once a second, the bar
                                        // lurched for 150ms, decelerated to a stop, then
                                        // sat frozen for 850ms. Twelve of them doing that
                                        // in unison was the twitchiest thing on the page.
                                        //
                                        // Now each travels its whole sampling period,
                                        // linearly, arriving exactly as the next sample
                                        // lands — constant data rate, constant speed. The
                                        // duration is the data's, not the designer's, so
                                        // it isn't a Motion token; motionEnabled still
                                        // turns it off, and then the bars just step.
                                        Behavior on height {
                                            enabled: Config.motionEnabled
                                            NumberAnimation {
                                                duration: SysInfo.interval
                                                easing.type: Easing.Linear
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── GPU ───────────────────────────────────────────────────────
                // Absent entirely when the driver publishes no utilisation, rather than
                // a gauge pinned at zero pretending the card is idle.
                Surface {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: SysInfo.hasGpu
                    elevation: Tokens.elevationNested
                    implicitHeight: gpuBox.implicitHeight + Tokens.spacingXl * 2

                    ColumnLayout {
                        id: gpuBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        anchors.margins: Tokens.spacingXl
                        spacing: Tokens.spacingMd

                        StyledText {
                            text: "Graphics"
                            variant: "body"
                            font.weight: Font.DemiBold
                        }

                        GaugeTile {
                            Layout.fillWidth: true
                            value:   SysInfo.gpu
                            history: SysInfo.gpuHistory
                            temp:    SysInfo.gpuTemp
                            caption: root.fact("DRIVER")
                        }

                        Divider { Layout.topMargin: Tokens.spacingXs }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingXs
                            StyledText {
                                Layout.fillWidth: true
                                text: "Video memory"
                                variant:  "caption"
                                emphasis: "dim"
                            }
                            StyledText {
                                rich: true
                                text: "<b>" + SysInfo.vramUsed.toFixed(1) + "</b> / "
                                    + SysInfo.vramTotal.toFixed(1) + " GB"
                                variant: "caption"
                            }
                        }

                        Meter {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            value: SysInfo.vramFraction
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // ── Memory ────────────────────────────────────────────────────
                // A meter, not a gauge. It's a capacity you fill, and the two numbers
                // that matter ("10.0 of 23.4 GB") are the answer — a ring would make
                // room for one of them and hide the other.
                Surface {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    elevation: Tokens.elevationNested
                    implicitHeight: memBox.implicitHeight + Tokens.spacingXl * 2

                    ColumnLayout {
                        id: memBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        anchors.margins: Tokens.spacingXl
                        spacing: Tokens.spacingMd

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Memory"
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                // Text token, not the accent — the meter carries identity.
                                text: Math.round(SysInfo.memFraction * 100) + "%"
                                variant: "headline"
                                font.weight: Font.Bold
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            rich: true
                            text: "<b>" + SysInfo.memUsed.toFixed(1) + " GB</b> of "
                                + SysInfo.memTotal.toFixed(1) + " GB"
                            variant:  "body"
                            emphasis: "muted"
                        }

                        Meter {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacingXs
                            implicitHeight: 10
                            value: SysInfo.memFraction
                        }

                        StyledText {
                            Layout.fillWidth: true
                            rich: true
                            text: "<i>Available, not free — the page cache is reclaimable and doesn't count as used.</i>"
                            variant:  "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }

                        Divider { Layout.topMargin: Tokens.spacingXs }

                        FactRow { key: "Graphics"; value: root.fact("GPU") }
                        FactRow { key: "VRAM";     value: root.fact("VRAM") }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ══ Hardware ══════════════════════════════════════════════════════
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Hardware"
                variant: "label"
                emphasis: "muted"
            }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: hwBox.implicitHeight + Tokens.spacingXl * 2

                GridLayout {
                    id: hwBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    columns: 2
                    columnSpacing: Tokens.spacingXxl
                    rowSpacing: Tokens.spacingSm

                    FactRow { key: "CPU";    glyph: ""; value: root.fact("CPU") }
                    FactRow { key: "Cores";  glyph: ""; value: root.fact("CORES") }
                    FactRow { key: "Memory"; glyph: ""; value: root.fact("RAM") }
                    FactRow { key: "Kernel"; glyph: ""; value: root.fact("KERNEL") }
                }
            }

            // ══ Compositor ════════════════════════════════════════════════════
            // The window manager gets the same treatment as the distro: a mark, a
            // version, and the build facts under it. It's the piece of software this
            // whole shell is a client of — the About page naming the kernel and the CPU
            // but not the compositor was a gap.
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Compositor"
                variant: "label"
                emphasis: "muted"
                visible: wmCard.visible
            }

            Surface {
                id: wmCard
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: wmBox.implicitHeight + Tokens.spacingXl * 2
                // Absent off Hyprland rather than a card full of em-dashes. specs.sh
                // emits nothing if hyprctl isn't there or isn't answering.
                visible: root.fact("WM_NAME") !== "—"

                ColumnLayout {
                    id: wmBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    spacing: Tokens.spacingLg

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingLg

                        // ── The logo ──────────────────────────────────────────
                        // The real mark, vendored: nothing on this system ships one, so
                        // it came from upstream into assets/logos — see the README there
                        // for provenance and why it needed cropping. Same Image code path
                        // as the distro hero, which gets its logo from os-release's LOGO=.
                        //
                        // NOT tinted, and that is a deliberate exception to "colours come
                        // from the palette": this is someone else's trademark and the
                        // gradient IS the mark. The nerd-font glyph it replaces had to be
                        // tinted, which is exactly why it was only ever a stand-in.
                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: Icons.logo("hyprland.svg")
                            // sourceSize rasterises the SVG AT this size rather than at
                            // its intrinsic one and scaling up — crisp vs mush.
                            sourceSize: Qt.size(72, 72)
                            // Layout.preferred*, NOT width/height: this Image is a direct
                            // child of a RowLayout, and setting width on a layout-managed
                            // item is undefined behaviour. (The distro hero next door sets
                            // width/height and gets away with it only because its Image is
                            // wrapped in a Loader, which is what the layout actually sees.)
                            Layout.preferredWidth:  72
                            Layout.preferredHeight: 72
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                StyledText {
                                    text: root.fact("WM_NAME") + " " + root.fact("WM_VERSION")
                                    variant: "headline"
                                }
                                Badge {
                                    label: root.fact("WM_SESSION")
                                    visible: root.fact("WM_SESSION") !== "—"
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                // The build's identity in one line: which branch, which
                                // commit, and whether the tree was clean when it was
                                // built. "clean" is the difference between this being
                                // 0.55.4 and being 0.55.4 plus someone's local patches.
                                text: {
                                    const parts = []
                                    if (root.fact("WM_BRANCH") !== "—") parts.push(root.fact("WM_BRANCH"))
                                    if (root.fact("WM_COMMIT") !== "—") parts.push(root.fact("WM_COMMIT"))
                                    if (root.fact("WM_DIRTY")  !== "—") parts.push(root.fact("WM_DIRTY"))
                                    return parts.join("  ·  ")
                                }
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── A version divergence, named ───────────────────────────
                    // Hyprland reports every library as "built against X, system has Y",
                    // and those disagree more often than you'd like — this machine runs
                    // Aquamarine 0.12.1 against a compositor built for 0.12.0. That's the
                    // backend doing all the DRM and input; when something is misbehaving
                    // in a way that makes no sense, this is the line you want to have
                    // already seen. It hides itself when everything matches.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: mismRow.implicitHeight + Tokens.spacingMd * 2
                        visible: root.fact("WM_LIB_MISMATCH") !== "—"
                                 && root.fact("WM_LIB_MISMATCH") !== ""
                        radius: Tokens.radiusSm
                        color:        Colors.alpha(Colors.warning, 0.10)
                        border.color: Colors.alpha(Colors.warning, 0.28)
                        border.width: Tokens.borderWidth

                        RowLayout {
                            id: mismRow
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingMd

                            StyledText { text: "󰀪"; color: Colors.warning; variant: "body" }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Library version mismatch: " + root.fact("WM_LIB_MISMATCH")
                                variant: "caption"
                                wrapMode: Text.WordWrap
                                opacity: 0.85
                            }
                        }
                    }

                    Divider {}

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Tokens.spacingXxl
                        rowSpacing: Tokens.spacingSm

                        FactRow { key: "Built";   glyph: ""; value: root.fact("WM_DATE") }
                        FactRow { key: "Commits"; glyph: ""; value: root.fact("WM_COMMITS") }
                        FactRow {
                            key: "Plugins"
                            glyph: ""
                            value: root.fact("WM_PLUGINS") === "—" ? "None loaded"
                                                                   : root.fact("WM_PLUGINS")
                        }
                        FactRow { key: "Monitors"; glyph: ""; value: String(Hypr.monitors.length) }
                    }

                    FactRow { key: "Libraries"; glyph: ""; value: root.fact("WM_LIBS") }
                }
            }

            // ══ Machine ═══════════════════════════════════════════════════════
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Machine"
                variant: "label"
                emphasis: "muted"
            }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: machineBox.implicitHeight + Tokens.spacingXl * 2

                GridLayout {
                    id: machineBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    columns: 2
                    columnSpacing: Tokens.spacingXxl
                    rowSpacing: Tokens.spacingSm

                    FactRow { key: "Board";    glyph: "\uEABE";  value: root.fact("BOARD") }
                    FactRow { key: "BIOS";     glyph: "\uF2DB";  value: root.fact("BIOS") }
                    FactRow { key: "Packages"; glyph: "\uEB29";  value: root.fact("PACKAGES") }
                    // The date of the last FULL upgrade, not of the newest package: any
                    // single -S would move a package mtime without the system having been
                    // brought forward. This is the number people actually mean.
                    FactRow {
                        key:   "Updated"
                        glyph: "\uEA82"
                        value: root.fact("LAST_UPGRADE")
                    }
                    // Total plus the breakdown, because "47s" invites "why" and one stage
                    // is usually carrying it. Here that's the kernel, at 21.7s.
                    FactRow {
                        key:   "Boot"
                        glyph: "\uEB44"
                        value: root.fact("BOOT") + (root.fact("BOOT_DETAIL") !== "\u2014"
                                                    ? "\n" + root.fact("BOOT_DETAIL") : "")
                    }
                    FactRow { key: "Uptime"; glyph: "\uF017"; value: root.fact("UPTIME") }
                }
            }

            // ══ Shell ═════════════════════════════════════════════════════════
            // The thing you are looking at. The page named the distro, the kernel, the
            // compositor and the display server, and not itself.
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Shell"
                variant: "label"
                emphasis: "muted"
            }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: shellBox.implicitHeight + Tokens.spacingXl * 2

                RowLayout {
                    id: shellBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    spacing: Tokens.spacingLg

                    // Quicktest's own mark — the one logo on this page that IS ours.
                    Image {
                        Layout.alignment: Qt.AlignVCenter
                        source: Icons.asset("QTGreen")
                        sourceSize: Qt.size(72, 72)
                        Layout.preferredWidth:  72
                        Layout.preferredHeight: 72
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText {
                                text: "Quicktest " + Config.version
                                variant: "headline"
                            }
                            // Hand-maintained; see Config.version for why it can't be
                            // derived. The update check compares it to the newest tag
                            // upstream.
                            Badge { label: "v" + Config.version; tint: Colors.success }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "on Quickshell " + root.fact("QS_VERSION")
                                + "  \u00b7  " + root.fact("QS_PACKAGER")
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Tokens.spacingXs

                        FactRow {
                            key:   "Repo"
                            glyph: "\uEA68"
                            value: Config.repo
                        }
                        FactRow {
                            key:   "Config"
                            glyph: "\uEB9C"
                            value: "~/.config/quicktest"
                        }
                    }
                }
            }

            // ══ Display server ════════════════════════════════════════════════
            // Wayland gets its own card rather than a row in the compositor's, because
            // it isn't part of Hyprland — it's the protocol Hyprland implements and
            // this entire shell is a client of. Conflating them is the same mistake as
            // filing the kernel under the distro.
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Display server"
                variant: "label"
                emphasis: "muted"
                visible: wlCard.visible
            }

            Surface {
                id: wlCard
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: wlBox.implicitHeight + Tokens.spacingXl * 2
                // Absent on an X11 session rather than a card of em-dashes claiming
                // Wayland facts about a machine that isn't running it.
                visible: root.fact("WL_DISPLAY") !== "\u2014"

                ColumnLayout {
                    id: wlBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    spacing: Tokens.spacingLg

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingLg

                        // The official mark, vendored alongside Hyprland's. A PNG, not
                        // an SVG, and not by choice: the vector lives in freedesktop's
                        // wayland-web GitLab, which 403s without a login. 117x150 is ample
                        // for the 72px it's drawn at. Papirus ships a scalable
                        // wayland.svg that was rejected — it's Papirus's restyled take on
                        // the mark, not the mark.
                        //
                        // Untinted, same reasoning as Hyprland's: the yellow is the logo.
                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: Icons.logo("wayland.png")
                            sourceSize: Qt.size(72, 72)
                            // Layout.preferred*, NOT width/height: this Image is a direct
                            // child of a RowLayout, and setting width on a layout-managed
                            // item is undefined behaviour. (The distro hero next door sets
                            // width/height and gets away with it only because its Image is
                            // wrapped in a Loader, which is what the layout actually sees.)
                            Layout.preferredWidth:  72
                            Layout.preferredHeight: 72
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                StyledText {
                                    text: "Wayland " + root.fact("WL_VERSION")
                                    variant: "headline"
                                }
                                Badge { label: root.fact("WL_DISPLAY") }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Protocols " + root.fact("WL_PROTOCOLS")
                                    + "  \u00b7  portal: " + root.fact("WL_PORTAL")
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Divider {}

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Tokens.spacingXxl
                        rowSpacing: Tokens.spacingSm

                        FactRow {
                            key:   "Session"
                            glyph: "\uEBD2"
                            value: root.fact("WM_SESSION") + "  \u00b7  " + root.fact("WM_NAME")
                        }
                        FactRow {
                            key:   "Protocols"
                            glyph: "\uEA66"
                            value: root.fact("WL_PROTOCOLS")
                        }
                        FactRow {
                            key:   "Portal"
                            glyph: "\uEB2D"
                            value: root.fact("WL_PORTAL")
                        }
                        // XWayland with a LIVE count, not just "installed". "Is anything
                        // still on X11" is the question this card exists to answer, and
                        // right now the answer is yes.
                        FactRow {
                            key:   "XWayland"
                            glyph: "\uEAE4"
                            value: root.fact("WL_XWAYLAND") === "\u2014"
                                 ? "Not running"
                                 : root.fact("WL_XWAYLAND") + "  \u00b7  "
                                   + root.fact("WL_XCLIENTS") + " X11 client"
                                   + (root.fact("WL_XCLIENTS") === "1" ? "" : "s")
                        }
                    }
                }
            }

            // ══ Displays ══════════════════════════════════════════════════════
            StyledText {
                Layout.topMargin: Tokens.spacingSm
                text: "Displays"
                variant: "label"
                emphasis: "muted"
            }

            Surface {
                Layout.fillWidth: true
                elevation: Tokens.elevationNested
                implicitHeight: displayBox.implicitHeight + Tokens.spacingXl * 2

                ColumnLayout {
                    id: displayBox
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingXl
                    spacing: Tokens.spacingLg

                    // ── The arrangement, to scale ─────────────────────────────
                    // Not decoration — Hyprland gives every monitor a real x/y/w/h in
                    // one shared coordinate space, so this is a scale drawing of your
                    // actual desktop. It's the only thing on this page that answers a
                    // question text can't: which screen is where.
                    MonitorMap {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                    }

                    Divider {}

                    Repeater {
                        model: Hypr.monitors

                        FactRow {
                            id: monitorRow
                            required property var modelData

                            key: monitorRow.modelData.name
                            // NOT rich. The description is an EDID string from the
                            // monitor's own firmware — a name from elsewhere, which is
                            // precisely what StyledText.rich must never be handed:
                            // Text.StyledText silently eats anything resembling markup,
                            // so a device whose name contains "<" would render wrong,
                            // and only that device.
                            //
                            // ── refreshRate is NOT on HyprlandMonitor ─────
                            // The type exposes x/y/width/height/scale/focused/
                            // description and nothing else. Refresh rate exists only in
                            // `lastIpcObject`, the raw hyprctl map the monitor was
                            // parsed from. Reading `.refreshRate` off the monitor gives
                            // undefined, and `.toFixed()` on undefined THROWS — which
                            // is exactly what this line used to do. qmllint can't catch
                            // it: modelData is a var, so the property is only resolved
                            // at runtime.
                            //
                            // Rounded to one place because Hyprland reports 165.001999,
                            // and a spec sheet claiming 165.002 Hz is worse than one
                            // claiming 165.
                            value: {
                                const m  = monitorRow.modelData
                                const hz = m.lastIpcObject?.refreshRate
                                return m.width + "×" + m.height
                                     + (hz !== undefined ? " @ " + hz.toFixed(1) + " Hz" : "")
                                     + (m.description ? "  ·  " + m.description : "")
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: Tokens.spacingLg }
        }
    }


    // The page scrolls on a small screen; on this one it doesn't, and the bar

    // hides itself when the content fits (see Scrollbar.scrollable). Declared as

    // a SIBLING of the Flickable, never a child — a Flickable reparents its

    // children into contentItem, so a scrollbar inside one scrolls away.

    Scrollbar { flickable: pageFlick }

    // ── GaugeTile ─────────────────────────────────────────────────────────────
    // The ring with the figure in its hole, and the last minute beside it. CPU and GPU
    // are the same readout of different silicon, so they're one component — two copies
    // would be two things to keep in step.
    component GaugeTile: RowLayout {
        id: gaugeTile

        property real value: 0
        property var  history: []
        property string caption: ""

        // °C, or -1 for "not reported". Optional: this tile is shared by CPU and GPU,
        // and a machine can report load for a chip whose temperature it can't read.
        property int temp: -1

        spacing: Tokens.spacingLg

        RadialGauge {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  104
            implicitHeight: 104
            thickness: 9
            // Travels for exactly one sampling period, so the ring tracks the load
            // continuously instead of ticking once a second. See RadialGauge.
            sampleInterval: SysInfo.interval
            value: gaugeTile.value

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    // The hero figure — text colour, not the accent. The ring around it
                    // already carries the identity, and a number in the accent would
                    // make the tile read as two things saying the same word.
                    text: Math.round(gaugeTile.value * 100)
                    variant: "display"
                    font.weight: Font.Bold
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "%"
                    variant:  "caption"
                    emphasis: "dim"
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

            Sparkline {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                values:   gaugeTile.history
                capacity: SysInfo.historyLength

                // ── Smooth ────────────────────────────────────────────────────
                // One sample a second across 60 slots meant the line sat still and then
                // JUMPED a slot sideways, once a second, forever. The glide slides it
                // continuously between samples instead, arriving exactly as the next one
                // lands. SysInfo keeps a surplus sample so the left edge stays covered.
                sampleInterval: SysInfo.interval
                gridlines: 1

                // Lightly damped. CPU load at 1Hz is genuinely spiky — a single busy
                // second from a compile spikes the whole chart — and 2 samples takes the
                // clatter off without flattening a real change into a ramp. NOT more:
                // this is a fixed 0..100% axis, so unlike the network's zoomed dBm view
                // the wobble here is to scale and worth seeing.
                damping: 2
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: "Last minute"
                    variant:  "caption"
                    emphasis: "dim"
                }
                // ── Temperature ───────────────────────────────────────────
                // Beside the load rather than in a temperatures section of its own.
                // "How hard is this chip working" and "how hot did that make it" are
                // one question asked twice, and splitting them across the page means
                // reading a spike here and hunting for its consequence there.
                //
                // Warning-tinted past 85°C: hot but not alarming is the normal state of
                // a loaded CPU — this box idles at 77°C — so a threshold that fires at
                // "warm" would cry wolf. Text colour otherwise, same rule as the hero
                // figure: the number is text and reads as text.
                StyledText {
                    visible: gaugeTile.temp > 0
                    text: gaugeTile.temp + " °C"
                    color: gaugeTile.temp >= 85 ? Colors.warning : Colors.fg
                    variant: "caption"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: gaugeTile.caption
                    variant:  "caption"
                    emphasis: "dim"
                }
            }
        }
    }

    component FactRow: RowLayout {
        id: factRow

        property string key:   ""
        property string value: ""
        property bool rich: false

        // ── The icon ──────────────────────────────────────────────────────────
        // Optional, and the slot is reserved either way so a card mixing iconned and
        // plain rows keeps its keys on one left edge. (`visible: false` on a Layout
        // item removes it from the layout — the same trap that made the Wi-Fi page's
        // reveal buttons shift everything sideways.)
        //
        // Dim, never accented: it's a bullet that happens to be a picture. If these
        // carried the focus colour, six of them in a card would out-shout the values
        // they're labelling.
        property string glyph: ""

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        Item {
            Layout.preferredWidth:  Tokens.iconSm
            Layout.alignment: Qt.AlignTop
            implicitHeight: factGlyph.implicitHeight

            StyledText {
                id: factGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                text:     factRow.glyph
                variant:  "caption"
                emphasis: "dim"
            }
        }

        StyledText {
            Layout.preferredWidth: 90
            Layout.alignment: Qt.AlignTop
            text:     factRow.key
            variant:  "caption"
            emphasis: "dim"
        }
        StyledText {
            Layout.fillWidth: true
            rich:     factRow.rich
            text:     factRow.value
            variant:  "caption"
            wrapMode: Text.WordWrap
        }
    }
}
