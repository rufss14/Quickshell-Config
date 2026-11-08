pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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
// ── On the live figures ───────────────────────────────────────────────────────
// Two deliberate calls, each against the obvious instinct:
//
//   · Each resource is a figure and ONE bar, not a ring and a trace. A ring is a two-slice
//     pie — it asks the eye to compare arcs where a bar lets it compare positions — and a
//     minute of history is not what anyone opens About for.
//   · The threads are a grid of cells in ONE hue, brighter as they work. Cores are
//     nominal — core 7 isn't "more" than core 3 — so a ramp across them would mean nothing.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var spec: SysInfo.spec   // scripts/specs.sh's key=value facts

    // Live sampling runs only while this page exists. The card's Loader destroys it
    // when you flip to another page, which is what stops the timer.
    Component.onCompleted:   { SysInfo.acquire(); SysInfo.loadSpec() }
    Component.onDestruction: SysInfo.release()


    function fact(key) { return root.spec[key] ? root.spec[key] : "—" }

    // ── Names that fit ────────────────────────────────────────────────────────
    // lspci's GPU string is "Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX
    // 6700/…]" — the marketing name is the last bracket. A CPU's "N-Core Processor" is
    // already said by the thread count beside it.
    function shortGpu(s) {
        if (!s || s === "—") return "—"
        const m = s.match(/\[([^\]]+)\][^\[]*$/)
        return m ? m[1] : s
    }
    function shortCpu(s) {
        if (!s || s === "—") return "—"
        return s.replace(/\s+\d+-Core Processor$/i, "").replace(/\s+with .*$/i, "")
    }

    SettingsPage {
        anchors.fill: parent
        bento:     true

        glyph:     "󰋼"
        title:     Translation.tr("About")
        titleTail: root.spec.HOST ? root.spec.HOST : ""
        subtitle:  root.fact("DISTRO") + "  ·  up " + root.fact("UPTIME")

        actions: ChipTray {
            ChipButton {
                label:  Translation.tr("Refresh")
                symbol: "refresh"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: SysInfo.loadSpec()
            }
        }

        // ══ Hero: what this machine is ════════════════════════════════════════
        // The distro logo and the hostname, and beside them the six facts people
        // actually come here for. It used to be the logo alone, with the facts in a
        // "Machine" card three screens down.
        Section {
            span:     3
            padding:  Tokens.spacingXl

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXxl

                // Loader-gated: an Image with an empty source resolves to Quickshell's
                // qs-blackhole placeholder and warns. A distro with no LOGO= in
                // os-release shows nothing rather than a broken icon.
                Loader {
                    active: String(root.spec.LOGO ?? "") !== ""
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: Image {
                        source: "file://" + root.spec.LOGO
                        // Rasterised AT this size, not scaled up from its own.
                        sourceSize: Qt.size(84, 84)
                        width:  84
                        height: 84
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 190
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingXs
                    StyledText {
                        Layout.fillWidth: true
                        text:    root.spec.HOST ? root.spec.HOST : "—"
                        variant: "display"
                        font.weight: Font.Bold
                        elide:   Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.fact("DISTRO")
                        variant: "body"
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.fact("KERNEL")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }

                // The spec sheet: two by three (three columns once the card is wide).
                GridLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    columns: width >= 720 ? 3 : 2
                    columnSpacing: Tokens.spacingLg
                    rowSpacing: Tokens.spacingMd

                    SpecCell { symbol: "memory";          key: "Processor"; value: root.shortCpu(root.fact("CPU")) + (root.fact("CORES") !== "—" ? " · " + root.fact("CORES") + " threads" : "") }
                    SpecCell { symbol: "developer_board"; key: "Graphics";  value: root.shortGpu(root.fact("GPU")) }
                    SpecCell { symbol: "memory_alt";      key: "Memory";    value: SysInfo.memTotal.toFixed(1) + " GB" }
                    SpecCell { symbol: "computer";        key: "Board";     value: root.fact("BOARD") }
                    SpecCell { symbol: "package";         key: "Packages";  value: root.fact("PACKAGES") + (root.fact("LAST_UPGRADE") !== "—" ? " · updated " + root.fact("LAST_UPGRADE") : "") }
                    SpecCell { symbol: "timer";           key: "Boot";      value: root.fact("BOOT"); help: root.fact("BOOT_DETAIL") }
                }
            }
        }

        // ══ Live: bars, and a grid of threads ═════════════════════════════════
        // No rings, no traces (2026-10-26): a ring is a two-slice pie and a trace of a minute
        // answers a question nobody opened About to ask. Each resource is its figure and ONE
        // bar — length is the value — and the threads are a grid of cells that light up with
        // their load, because twelve of them as bars were twelve things to compare for no gain.
        Section {
            span:   3
            glyph:  "󰓅"
            title:  Translation.tr("Right now")
            help:   Translation.tr("Sampled once a second while this page is open. Memory counts what is not available — the page cache is reclaimable and doesn't count.")
            accent: Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXxl

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingLg

                    LoadBar {
                        title:  Translation.tr("Processor")
                        value:  SysInfo.cpu
                        line:   (SysInfo.cpuTemp > 0 ? SysInfo.cpuTemp + " °C" : "")
                        hot:    SysInfo.cpuTemp >= 85
                    }
                    LoadBar {
                        visible: SysInfo.hasGpu
                        title:  Translation.tr("Graphics")
                        value:  SysInfo.gpu
                        line:   (SysInfo.gpuTemp > 0 ? SysInfo.gpuTemp + " °C  ·  " : "")
                                + SysInfo.vramUsed.toFixed(1) + " / " + SysInfo.vramTotal.toFixed(1) + " GB"
                        hot:    SysInfo.gpuTemp >= 85
                    }
                    LoadBar {
                        title:  Translation.tr("Memory")
                        value:  SysInfo.memFraction
                        line:   SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(1) + " GB"
                    }
                    LoadBar {
                        visible: SysInfo.swapTotal > 0.05
                        title:  Translation.tr("Swap")
                        value:  SysInfo.swapFraction
                        line:   SysInfo.swapUsed.toFixed(1) + " / " + SysInfo.swapTotal.toFixed(1) + " GB"
                    }
                    LoadBar {
                        title:  Translation.tr("Disk")
                        value:  SysInfo.diskUtil
                        line:   "↓ " + Storage.bytes(SysInfo.diskRead) + "/s   ↑ " + Storage.bytes(SysInfo.diskWrite) + "/s"
                    }
                }

                // Threads: a cell each, brighter as it works.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: Translation.tr("Threads")
                        variant: "caption"
                        emphasis: "dim"
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: SysInfo.cores.length

                            Rectangle {
                                id: core
                                required property int index
                                readonly property real load: SysInfo.cores[core.index] ?? 0
                                width:  30
                                height: 30
                                radius: Tokens.radiusSm
                                // A floor, so an idle thread is a cell rather than a gap.
                                color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10 + 0.80 * core.load)
                                // Settles in Motion.settle and rests for the rest of the
                                // second — a glide across the whole period kept the page
                                // redrawing at the refresh rate.
                                Behavior on color {
                                    enabled: Config.motionEnabled
                                    ColorAnimation { duration: Math.min(SysInfo.interval, Motion.settle) }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: Math.round(core.load * 100)
                                    variant: "caption"
                                    color: core.load > 0.55 ? Colors.of(QsWindow.window).fgOnPrimary
                                                            : Colors.of(QsWindow.window).fgMuted
                                }
                            }
                        }
                    }
                }
            }
        }

        // ══ Software: three stacks, one row ═══════════════════════════════════
        // Hyprland, Wayland and this shell, each a logo, a version and one line. The
        // build details that filled three cards are each one's tip.
        Section {
            span:   3
            glyph:  "󰆍"
            title:  Translation.tr("Software")
            accent: Colors.of(QsWindow.window).primary

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 640 ? 3 : 1
                columnSpacing: Tokens.spacingXl
                rowSpacing: Tokens.spacingMd

                // Vendored marks, untinted: someone else's trademark, the colours ARE
                // the mark (assets/logos/README.md).
                Stack {
                    visible: root.fact("WM_NAME") !== "—"
                    logo:    Icons.logo("hyprland.svg")
                    name:    root.fact("WM_NAME") + " " + root.fact("WM_VERSION")
                    line:    root.fact("WM_PLUGINS") === "—" ? "No plugins" : "Plugins: " + root.fact("WM_PLUGINS")
                    help:    "Built " + root.fact("WM_DATE") + " from " + root.fact("WM_BRANCH") + " " + root.fact("WM_COMMIT")
                           + " (" + root.fact("WM_DIRTY") + "), " + root.fact("WM_COMMITS") + " commits. Libraries: " + root.fact("WM_LIBS")
                }
                Stack {
                    visible: root.fact("WL_VERSION") !== "—"
                    logo:    Icons.logo("wayland.png")
                    name:    "Wayland " + root.fact("WL_VERSION").replace(/-\d+$/, "")
                    line:    root.fact("WL_XWAYLAND") === "—" ? "XWayland not running"
                           : (root.fact("WL_XCLIENTS") === "1" ? "1 X11 client" : root.fact("WL_XCLIENTS") + " X11 clients")
                    help:    "Display " + root.fact("WL_DISPLAY") + ". Protocols " + root.fact("WL_PROTOCOLS")
                           + ", portal: " + root.fact("WL_PORTAL") + ". XWayland " + root.fact("WL_XWAYLAND") + "."
                }
                Stack {
                    logo:    Icons.logo("quickshell.svg")
                    name:    "Quicktest " + Config.version
                    line:    "on Quickshell " + root.fact("QS_VERSION")
                    help:    "Repo " + Config.repo + ". Config " + Quickshell.shellDir + ". "
                           + (Tokens.hasSymbols ? "Icons bundled (" + Tokens.fontSymbols + ", " + Tokens.fontGlyphs + ")."
                                                : "Icon fonts missing from assets/fonts — reinstall the shell.")
                }
            }

            // ── A version divergence, named ───────────────────────────────────
            // "Built against X, system has Y" for Hyprland's libraries: when something
            // misbehaves in a way that makes no sense, this is the line to have seen.
            // Hidden when everything matches.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.fact("WM_LIB_MISMATCH") !== "—" && root.fact("WM_LIB_MISMATCH") !== ""
                text: "Library version mismatch: " + root.fact("WM_LIB_MISMATCH")
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }
        }

        // ══ Displays ══════════════════════════════════════════════════════════
        // A scale drawing of the desktop (MonitorMap) beside each monitor's mode.
        Section {
            span:     3
            glyph:    "󰍹"
            title:    Translation.tr("Displays")
            subtitle: Hypr.monitors.length + (Hypr.monitors.length === 1 ? " monitor" : " monitors")
            accent:   Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXl

                MonitorMap {
                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 72
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: Hypr.monitors

                        FactRow {
                            id: monitorRow
                            required property var modelData
                            key: monitorRow.modelData.name
                            // NOT rich: the description is an EDID string from the
                            // monitor's firmware, and StyledText eats anything that looks
                            // like markup. Refresh rate lives only in lastIpcObject (the
                            // type has no refreshRate), rounded — Hyprland says 165.002.
                            value: {
                                const m  = monitorRow.modelData
                                const hz = m.lastIpcObject?.refreshRate
                                return m.width + "×" + m.height
                                    + (hz !== undefined ? " @ " + Math.round(hz) + " Hz" : "")
                                    + (m.description ? "  ·  " + m.description : "")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── SpecCell — one fact of the hero's spec sheet ──────────────────────────
    component SpecCell: RowLayout {
        id: cell
        property string symbol: ""
        property string key: ""
        property string value: ""
        property string help: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 0
        spacing: Tokens.spacingSm

        HelpTip { text: cell.help }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.14)
            MaterialIcon {
                anchors.centerIn: parent
                name: cell.symbol
                color: Colors.of(QsWindow.window).primary
                font.pixelSize: Tokens.iconMd
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: cell.key
                variant: "caption"
                emphasis: "dim"
            }
            StyledText {
                Layout.fillWidth: true
                text: cell.value
                variant: "caption"
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }
    }

    // ── LoadBar — a name, its figure, one bar, one line ───────────────────────
    component LoadBar: ColumnLayout {
        id: lb
        property string title: ""
        property real   value: 0
        property string line:  ""
        property bool   hot:   false

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            StyledText {
                text: lb.title
                variant: "body"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: lb.line
                variant: "caption"
                color: lb.hot ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                elide: Text.ElideLeft
            }
            StyledText {
                Layout.minimumWidth: 44
                horizontalAlignment: Text.AlignRight
                text: Math.round(lb.value * 100) + "%"
                variant: "title"
                font.weight: Font.Bold
            }
        }
        Meter {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
            value: lb.value
            fillDuration: Math.min(SysInfo.interval, Motion.settle)
        }
    }

    // ── Stack — one piece of software: its mark, version and one line ─────────
    component Stack: RowLayout {
        id: st
        property url    logo
        property string name: ""
        property string line: ""
        property string help: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 0
        spacing: Tokens.spacingMd

        HelpTip { id: stTip; text: st.help }

        Image {
            Layout.alignment: Qt.AlignVCenter
            source: st.logo
            sourceSize: Qt.size(44, 44)
            Layout.preferredWidth:  44
            Layout.preferredHeight: 44
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text: st.name
                    variant: "body"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                MaterialIcon {
                    visible: st.help !== ""
                    name: "info"
                    color: Colors.of(QsWindow.window).fgDim
                    font.pixelSize: Tokens.iconSm
                    opacity: stTip.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                Item { Layout.fillWidth: true }
            }
            StyledText {
                Layout.fillWidth: true
                text: st.line
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
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

            MaterialIcon {
                id: factGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                glyph:     factRow.glyph
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
