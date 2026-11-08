import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../services/setupplan.js" as Plan
import "../../state"
import "wizard"

// ── SetupWizard ───────────────────────────────────────────────────────────────
// The first-run setup as pages — WelcomePanel hosts it. The same plan as SetupFlow (Settings › Setup),
// walked one topic at a time:
//
//   0  Welcome        what was found on this machine, how ready it is, the five topics (each a link)
//   1  Packages       a preflight (network, disk, pacman, root), the shell's packages, an AUR helper, pywal
//   2  Morphing       the metaball fusion plugin, with a picture of it
//   3  Hyprland       two ways to wire the shell in, as cards; autostart
//   4  Integrations   Spotify bridge and the other optional extras, as a grid
//   5  Colours        the live palette, theming your apps
//   6  Style          light or dark, icon shape, corners, spacing, motion — applied as you pick, behind the card
//   7  Review         the plan as a timeline, the password (once), THEN the one button, the run, the recap
//
// Pages only CHOOSE: each card is a tick (Setup.selectedIds — the recommended steps are ticked, extras are
// not) and nothing is installed until the last page, so root is asked once and a dependency chain (an AUR
// package needs an AUR helper needs the base tools) is ordered by the plan, not by which page you visited
// first. The cards, the password field and the run are the same components SetupFlow uses.
//
// ── The look (2026-10-18) ─────────────────────────────────────────────────────
// The first paged version was the old wizard's flat rows and read as a form. This one is built from the
// panels' own vocabulary: cookie plates (SetupCookie) instead of square chips, cards that spring in one
// after another (PopIn) and lean toward the pointer, a page that rises into place (ViewEnter), a ring for
// "how ready is this machine" (RadialGauge), a progress strip whose current stop opens up to name its page,
// a palette strip that is the colours the shell is wearing right now, and a Review page that draws the
// plan as a timeline. Nothing is decoration the logic doesn't back: every chip, ring and stat is read
// from the scan or the plan.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal closeRequested()

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    property int page: 0
    readonly property int lastPage: 7
    readonly property var pageTitles: ["Welcome", "Packages", "Morphing", "Hyprland", "Integrations", "Colours", "Style", "Review"]
    // Entrances play after creation, not during it (a ViewEnter / PopIn plays when `active` TURNS true).
    property bool opened: false
    Component.onCompleted: { SudoLock.check(); HyprConfig.acquire(); Qt.callLater(function () { root.opened = true }) }

    // A plan is running or has just run: the last page is the progress and the recap, and the way
    // back to choosing is its Review button.
    readonly property bool inRun: Setup.run.active || Setup.run.done

    function next() { if (root.page < root.lastPage) root.page++ }
    function back() { if (root.page > 0) root.page-- }
    function goto(i) { if (!Setup.run.active) root.page = Math.max(0, Math.min(root.lastPage, i)) }
    function on(i) { return root.opened && root.page === i }

    // Read your keybinds (scripts/hypr-config.py) while the wizard is up, to show the ones that open the shell's
    // own things. Released with it.
    Component.onDestruction: HyprConfig.release()
    readonly property var tryBinds: {
        const want = [
            { key: "launcher toggle", label: "launcher" }, { key: "overview toggle", label: "overview" },
            { key: "dock toggle", label: "dock" }, { key: "gamemode toggle", label: "game mode" }
        ]
        const out = []
        for (const w of want) {
            const b = HyprConfig.binds.find(x => JSON.stringify(x.action ?? {}).indexOf("call " + w.key) >= 0)
            if (b && b.combo) out.push({ label: w.label, combo: b.combo })
        }
        return out
    }

    readonly property bool anyTodo: Setup.steps.some(s => s.state === "todo")
    // The summary line under the page: what's ticked and what it costs.
    readonly property string tally: Setup.plan.count === 0 ? (root.anyTodo ? "Nothing selected" : "Nothing left to install")
        : Setup.plan.count + (Setup.plan.count === 1 ? " step" : " steps") + " selected  ·  " + Plan.etaText(Setup.plan.eta)

    readonly property bool needPw: Setup.plan.root && !Setup.polkitReady
    readonly property bool canStart: Setup.plan.count > 0 && !Setup.fatalBlock && !Setup.busy && !SudoLock.locked
    function start() {
        if (root.needPw && wizardReviewPage.pw.password.length === 0) { wizardReviewPage.pw.focusField(); return }
        Setup.startPlan(wizardReviewPage.pw.password)
    }

    // What a topic's steps say: how many are still to do, whether they are all done.
    function topic(ids) {
        const s = Setup.steps.filter(x => ids.indexOf(x.id) >= 0)
        const todo = s.filter(x => x.state === "todo").length
        return { n: s.length, todo: todo, done: s.length > 0 && s.every(x => x.state === "done"),
                 blocked: s.length > 0 && s.every(x => x.state === "blocked") }
    }
    function topicText(t, optional) {
        return t.done ? "Ready" : t.blocked ? "Unavailable" : t.todo > 0 ? t.todo + " to do" : optional ? "Optional" : "Ready"
    }

    // Essentials: everything that isn't an optional extra. The ring on the welcome page.
    readonly property var essentials: Setup.steps.filter(s => s.group !== "extras")
    readonly property int readyCount: root.essentials.filter(s => s.state === "done").length
    readonly property real readyRatio: root.essentials.length === 0 ? 0 : root.readyCount / root.essentials.length

    // What the scan found, as chips: [{ text, level }]
    readonly property var scanChips: {
        const f = Setup.facts
        const out = []
        out.push({ text: f.arch ? "Arch Linux" : "Not Arch", level: f.arch ? "ok" : "bad" })
        Setup.compat.forEach(function (c) {
            if (c.id === "qt") return
            out.push({ text: c.label + (c.have ? " " + c.have : ""), level: c.state === "ok" ? "ok" : c.state === "warn" ? "warn" : "unknown" })
        })
        if (f.gpu) out.push({ text: f.gpu + " graphics", level: "ok" })
        if (f.aurHelper !== "none") out.push({ text: f.aurHelper, level: "ok" })
        return out
    }
    // The preflight on the Packages page.
    readonly property var preflight: {
        const f = Setup.facts
        const gb = Math.round(f.diskMiB / 102.4) / 10
        return [
            { text: f.network === true ? "Online" : f.network === false ? "Offline" : "Network unknown",
              level: f.network === true ? "ok" : f.network === false ? "bad" : "unknown" },
            { text: f.diskMiB <= 0 ? "Disk unknown" : gb + " GB free",
              level: f.diskMiB <= 0 ? "unknown" : f.diskMiB < 1500 ? "bad" : f.diskMiB < 4000 ? "warn" : "ok" },
            { text: f.pacmanLock || f.pacmanRunning ? "pacman is busy" : "pacman is free",
              level: f.pacmanLock || f.pacmanRunning ? "bad" : "ok" },
            { text: Setup.polkitReady ? "Password dialog ready" : f.sudo ? "sudo available" : "No sudo found",
              level: Setup.polkitReady || f.sudo ? "ok" : "warn" }
        ]
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacingLg

        // ── Progress — the current stop opens up to name its page; each stop is a link ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            Repeater {
                model: root.lastPage + 1
                delegate: Rectangle {
                    id: seg
                    required property int index
                    readonly property bool here: seg.index === root.page
                    readonly property bool past: seg.index < root.page
                    Layout.fillWidth: true
                    Layout.preferredWidth: seg.here ? 132 : 22
                    Layout.preferredHeight: 22
                    radius: Tokens.corner(Config.barShape, height / 2)
                    color: seg.here ? Colors.of(QsWindow.window).primary
                         : seg.past ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.34)
                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, segHover.hovered ? 0.16 : 0.07)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: Motion.emphasized; easing.type: Motion.overshoot; easing.overshoot: 1.05 }
                    }
                    clip: true

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingMd
                        horizontalAlignment: Text.AlignHCenter
                        text: root.pageTitles[seg.index]
                        variant: "caption"; font.weight: Font.Medium
                        color: Colors.of(QsWindow.window).fgOnPrimary
                        elide: Text.ElideRight
                        opacity: seg.here ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: seg.past
                        name: "check"
                        color: Colors.of(QsWindow.window).primary
                        font.pixelSize: Tokens.iconSm - 2
                    }
                    HoverHandler { id: segHover; enabled: !Setup.run.active }
                    TapHandler { enabled: !Setup.run.active; onTapped: root.goto(seg.index) }
                }
            }
        }

        // ── Pages ────────────────────────────────────────────────────────────
        Item {
            id: pageHost
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.page === 0 ? wizardWelcomePage.p0.implicitHeight
                                  : root.page === 1 ? wizardPackagesPage.p1.implicitHeight
                                  : root.page === 2 ? wizardMorphPage.p2.implicitHeight
                                  : root.page === 3 ? wizardHyprlandPage.p3.implicitHeight
                                  : root.page === 4 ? wizardIntegrationsPage.p4.implicitHeight
                                  : root.page === 5 ? wizardColoursPage.p5.implicitHeight
                                  : root.page === 6 ? wizardStylePage.p6.implicitHeight
                                  :                   wizardReviewPage.p7.implicitHeight
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }

            // ═══ 0 — Welcome ═════════════════════════════════════════════════
            WizardWelcomePage {
                id: wizardWelcomePage
                wizard: root
            }

            // ═══ 1 — Packages ════════════════════════════════════════════════
            WizardPackagesPage {
                id: wizardPackagesPage
                wizard: root
            }

            // ═══ 2 — Morphing system ═════════════════════════════════════════
            WizardMorphPage {
                id: wizardMorphPage
                wizard: root
            }

            // ═══ 3 — Hyprland ════════════════════════════════════════════════
            WizardHyprlandPage {
                id: wizardHyprlandPage
                wizard: root
            }

            // ═══ 4 — Integrations ════════════════════════════════════════════
            WizardIntegrationsPage {
                id: wizardIntegrationsPage
                wizard: root
            }

            // ═══ 5 — Colours ═════════════════════════════════════════════════
            WizardColoursPage {
                id: wizardColoursPage
                wizard: root
            }

            // ═══ 6 — Style ═══════════════════════════════════════════════════
            // Every control here is the shell's own preference, written as you click, so the card and the shell
            // behind it change at once — there is nothing to apply and nothing to undo but the control itself.
            WizardStylePage {
                id: wizardStylePage
                wizard: root
            }

            // ═══ 7 — Review, run, recap ══════════════════════════════════════
            WizardReviewPage {
                id: wizardReviewPage
                wizard: root
            }
        }

        // ── Nav ──────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !root.inRun
            spacing: Tokens.spacingSm

            PanelButton {
                visible: root.page > 0
                variant: "ghost"
                accent: Colors.of(QsWindow.window).primary
                symbol: "chevron_left"
                label: Translation.tr("Back")
                onActivated: root.back()
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                horizontalAlignment: Text.AlignHCenter
                visible: root.page > 0 && root.page < root.lastPage
                text: root.tally
                variant: "caption"; emphasis: "dim"
            }
            Item { Layout.fillWidth: true; visible: root.page === 0 || root.page === root.lastPage }

            PanelButton {
                visible: root.page < root.lastPage
                variant: "primary"
                accent: Colors.of(QsWindow.window).primary
                symbol: "chevron_right"
                label: root.page === 0 ? "Get started" : "Next"
                onActivated: root.next()
            }
            PanelButton {
                visible: root.page === root.lastPage
                variant: "primary"
                accent: Colors.of(QsWindow.window).primary
                symbol: Setup.plan.count === 0 ? "check" : "play_arrow"
                label: Setup.plan.count === 0 ? "Done"
                     : Setup.plan.count === 1 ? "Set up 1 thing" : "Set up " + Setup.plan.count + " things"
                enabled: Setup.plan.count === 0 || root.canStart
                onActivated: Setup.plan.count === 0 ? root.closeRequested() : root.start()
            }
        }
    }

}
