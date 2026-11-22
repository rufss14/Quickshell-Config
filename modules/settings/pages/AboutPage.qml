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


    function fact(key) { return root.spec[key] ? root.spec[key] : "n/a" }

    // ── Names that fit ────────────────────────────────────────────────────────
    // lspci's GPU string is "Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX
    // 6700/…]" — the marketing name is the last bracket. A CPU's "N-Core Processor" is
    // already said by the thread count beside it.
    function shortGpu(s) {
        if (!s || s === "n/a") return "n/a"
        const m = s.match(/\[([^\]]+)\][^\[]*$/)
        return m ? m[1] : s
    }
    function shortCpu(s) {
        if (!s || s === "n/a") return "n/a"
        return s.replace(/\s+\d+-Core Processor$/i, "").replace(/\s+with .*$/i, "")
    }

    SettingsPage {
        anchors.fill: parent
        grouped:     true
        groupLayout: "columns"

        glyph:     "󰋼"
        title:     Translation.tr("About")
        titleTail: root.spec.HOST ? root.spec.HOST : ""
        subtitle:  root.fact("DISTRO") + "  ·  up " + root.fact("UPTIME")

        actions: ChipTray {
            // scripts/doctor.sh: versions, missing packages, how the shell runs, its latest
            // warnings, with home / user / host names taken out. For pasting into a bug report.
            ChipButton {
                label:  SysInfo.diagnostics === "running" ? Translation.tr("Collecting…")
                      : SysInfo.diagnostics === "copied"  ? Translation.tr("Copied")
                      : SysInfo.diagnostics === "failed"  ? Translation.tr("Couldn't collect")
                      : Translation.tr("Copy diagnostics")
                symbol: SysInfo.diagnostics === "copied" ? "check" : "content_copy"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: SysInfo.copyDiagnostics()
            }
            ChipButton {
                label:  Translation.tr("Refresh")
                symbol: "refresh"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: SysInfo.loadSpec()
            }
        }

        // ══ What this machine is ══════════════════════════════════════════════
        // The distro logo and the hostname, then the six facts people come here for, in a
        // two-by-three sheet whose values wrap rather than cut (a GPU's marketing name is long).
        Section {
            grouped:  true
            symbol:   "computer"
            title:    Translation.tr("This machine")
            subtitle: root.fact("KERNEL")
            accent:   Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                // Loader-gated: an Image with an empty source resolves to Quickshell's
                // qs-blackhole placeholder and warns. A distro with no LOGO= in
                // os-release shows nothing rather than a broken icon.
                Loader {
                    active: String(root.spec.LOGO ?? "") !== ""
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: Image {
                        source: "file://" + root.spec.LOGO
                        // Rasterised AT this size, not scaled up from its own.
                        sourceSize: Qt.size(64, 64)
                        width:  64
                        height: 64
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingXs
                    StyledText {
                        Layout.fillWidth: true
                        text:    root.spec.HOST ? root.spec.HOST : "…"
                        variant: "headline"
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
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: 2
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingMd

                SpecCell { symbol: "memory";          key: Translation.tr("Processor"); value: root.shortCpu(root.fact("CPU")) + (root.fact("CORES") !== "n/a" ? " · " + root.fact("CORES") + " threads" : "") }
                SpecCell { symbol: "developer_board"; key: Translation.tr("Graphics");  value: root.shortGpu(root.fact("GPU")) }
                SpecCell { symbol: "memory_alt";      key: Translation.tr("Memory");    value: SysInfo.memTotal.toFixed(1) + " GB" }
                SpecCell { symbol: "computer";        key: Translation.tr("Board");     value: root.fact("BOARD") }
                SpecCell { symbol: "package";         key: Translation.tr("Packages");  value: root.fact("PACKAGES") + (root.fact("LAST_UPGRADE") !== "n/a" ? " · updated " + root.fact("LAST_UPGRADE") : "") }
                SpecCell { symbol: "timer";           key: Translation.tr("Boot");      value: root.fact("BOOT"); help: root.fact("BOOT_DETAIL") }
            }
        }

        // ══ Live: one bar per resource ════════════════════════════════════════
        // Each resource is its figure and ONE bar (length is the value): a ring is a two-slice
        // pie, and a trace of a minute answers a question nobody opened About to ask.
        Section {
            grouped: true
            symbol:  "speed"
            title:   Translation.tr("Right now")
            help:    Translation.tr("Sampled once a second while this page is open. Memory counts what is not available: the page cache is reclaimable and doesn't count.")
            accent:  Colors.of(QsWindow.window).primary

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

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
        }

        // ══ Threads: a cell each, brighter as it works ════════════════════════
        // Cores are nominal (core 7 isn't "more" than core 3), so one hue and no ramp across them.
        Section {
            grouped:  true
            symbol:   "memory"
            title:    Translation.tr("Threads")
            subtitle: SysInfo.cores.length + " " + Translation.tr("threads")
            accent:   Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingXs

                Repeater {
                    model: SysInfo.cores.length

                    Rectangle {
                        id: core
                        required property int index
                        readonly property real load: SysInfo.cores[core.index] ?? 0
                        // Wide enough for "100%".
                        width:  42
                        height: 28
                        radius: Tokens.radiusSm
                        // A floor, so an idle thread is a cell rather than a gap.
                        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10 + 0.80 * core.load)
                        // Settles in Motion.settle and rests for the rest of the second: a glide
                        // across the whole period kept the page redrawing at the refresh rate.
                        Behavior on color {
                            enabled: Config.motionEnabled
                            ColorAnimation { duration: Math.min(SysInfo.interval, Motion.settle) }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: Math.round(core.load * 100) + "%"
                            variant: "micro"
                            color: core.load > 0.55 ? Colors.of(QsWindow.window).fgOnPrimary
                                                    : Colors.of(QsWindow.window).fgMuted
                        }
                    }
                }
            }
        }

        // ══ Software: three stacks ════════════════════════════════════════════
        // Hyprland, Wayland and this shell, each a logo, a version and one line. The build
        // details that filled three cards are each one's tip.
        Section {
            grouped: true
            symbol:  "terminal"
            title:   Translation.tr("Software")
            accent:  Colors.of(QsWindow.window).primary

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // Vendored marks, untinted: someone else's trademark, the colours ARE
                // the mark (assets/logos/README.md).
                Stack {
                    visible: root.fact("WM_NAME") !== "n/a"
                    logo:    Icons.logo("hyprland.svg")
                    name:    root.fact("WM_NAME") + " " + root.fact("WM_VERSION")
                    line:    root.fact("WM_PLUGINS") === "n/a" ? "No plugins" : "Plugins: " + root.fact("WM_PLUGINS")
                    help:    "Built " + root.fact("WM_DATE") + " from " + root.fact("WM_BRANCH") + " " + root.fact("WM_COMMIT")
                           + " (" + root.fact("WM_DIRTY") + "), " + root.fact("WM_COMMITS") + " commits. Libraries: " + root.fact("WM_LIBS")
                }
                Stack {
                    visible: root.fact("WL_VERSION") !== "n/a"
                    logo:    Icons.logo("wayland.png")
                    name:    "Wayland " + root.fact("WL_VERSION").replace(/-\d+$/, "")
                    line:    root.fact("WL_XWAYLAND") === "n/a" ? "XWayland not running"
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
                                                : "Icon fonts missing from assets/fonts, reinstall the shell.")
                }
            }

            // ── A version divergence, named ───────────────────────────────────
            // "Built against X, system has Y" for Hyprland's libraries: when something
            // misbehaves in a way that makes no sense, this is the line to have seen.
            // Hidden when everything matches. The script joins the entries with a space only,
            // so each one is split off here.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.fact("WM_LIB_MISMATCH") !== "n/a" && root.fact("WM_LIB_MISMATCH") !== ""
                text: Translation.tr("Library version mismatch") + ": "
                      + root.fact("WM_LIB_MISMATCH").replace(/\)\s+(?=\S)/g, ")  ·  ")
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }
        }

        // ══ Displays ══════════════════════════════════════════════════════════
        // A scale drawing of the desktop (MonitorMap) and each monitor's mode. It counts the
        // screens Hyprland has switched on; Displays lists every connected one, turned off or not.
        Section {
            grouped:  true
            symbol:   "monitor"
            title:    Translation.tr("Displays")
            subtitle: Hypr.monitors.length === 1 ? Translation.tr("1 active display")
                                                 : Translation.tr("%1 active displays").arg(Hypr.monitors.length)
            help:     Translation.tr("Counts the screens Hyprland has switched on. The Displays page also lists connected screens that are turned off.")
            accent:   Colors.of(QsWindow.window).primary

            MonitorMap {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Hypr.monitors.length > 0

                Repeater {
                    model: Hypr.monitors

                    FactRow {
                        id: monitorRow
                        required property var modelData
                        key: monitorRow.modelData.name
                        // NOT rich: the description is an EDID string from the
                        // monitor's firmware, and StyledText eats anything that looks
                        // like markup. Refresh rate lives only in lastIpcObject (the
                        // type has no refreshRate), rounded: Hyprland says 165.002.
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
                wrapMode: Text.WordWrap
                maximumLineCount: 3
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
                Layout.fillHeight: false
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
