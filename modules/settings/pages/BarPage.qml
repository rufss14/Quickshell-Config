pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../state"
import ".."
import "../../../services"
import "../../../config/modules.js" as Catalogue

// ── BarPage — Bar › Modules: the bar AND the sidebar ──────────────────────────
// Every module, wherever it stands, on one page (the user's ask, 2026-11-08: "they
// both can use the same modules and should have the same customization"). It was two:
// this page arranged the bar, and Sidebar & dock › Sidebar had a row of on/off chips,
// an Arrange card, a hero picker and the peeks — plus a tab each for the dock and the
// stats. A module has one place and one set of settings, so it has one page.
//
// Two cards, and the REAL bar and sidebar above them:
//   the surfaces  armed while this page is open (UiState.arrange): press a module on the
//                 bar or the sidebar to pick it, drag it along a surface, across to the
//                 other, or down onto the library to take it off. A scaled map of both
//                 surfaces stood here for one round; the user found clicking the real
//                 things easier and the map a lot of page for it (2026-11-08).
//   (the module)  its inspector (ModuleInspector): where it stands, its colour, its
//                 switches, and for the dock and Stats their own settings.
//   Library       everything, on shelves (ModuleLibrary) — what replaced the "Not on
//                 the bar" card.
//
// The file keeps its name (BarPage.qml) so every link to "Bar › Modules" — the desktop
// entry, the search index, remembered pages — still lands here.
//
// ── Arranging is ON while the page is open ────────────────────────────────────
// It used to be a button, after a round where the page armed itself and the bar was
// covered in drop targets whether or not you wanted to move anything. With the map gone
// the real surfaces ARE the picker, and a click there only picks while arranging, so the
// user chose (2026-11-08) to arm it on open again. Done turns it off early; leaving the
// page always disarms, so it can't be left on by switching views, closing the window or
// a reload.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    PreviewModules { id: previewModules }

    // ── Live counts, not a description ────────────────────────────────────────
    readonly property int onBar: {
        let n = 0
        for (const r of Config.regionIds) for (const g of (Config.layout[r] ?? [])) n += g.length
        return n
    }
    readonly property int onSide: {
        let n = 0
        for (const r of Config.sidebarRegionIds) for (const g of (Config.sidebarLayout[r] ?? [])) n += g.length
        return n
    }

    Component.onDestruction: UiState.arrange = false

    // Arm the real surfaces, and open on something rather than an empty "pick one"
    // card: the first module on the bar, unless one is already picked.
    Component.onCompleted: {
        UiState.arrange = true
        if (UiState.barInspectModule !== "") return
        for (const region of Config.regionIds)
            for (const g of (Config.layout[region] ?? []))
                if (g.length > 0) { UiState.inspectBarModule(g[0]); return }
    }

    readonly property var picked: UiState.barInspectModule !== "" ? Catalogue.info(UiState.barInspectModule) : null
    readonly property string pickedWhere: {
        void Config.layout; void Config.sidebarLayout
        return UiState.barInspectModule !== "" ? Config.surfaceOf(UiState.barInspectModule) : ""
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰍜"
        title:     Translation.tr("Modules")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.onBar + " on the bar  ·  " + root.onSide + " on the sidebar"

        actions: ChipTray {
            ChipButton {
                label:  UiState.arrange ? "Done" : "Arrange"
                symbol: UiState.arrange ? "check" : "drag_pan"
                on:     UiState.arrange
                tint:   Colors.of(QsWindow.window).primary
                onActivated: UiState.arrange = !UiState.arrange
            }
        }

        // ══ The selected one ══════════════════════════════════════════════════
        // Its name is the card's title.
        Section {
            span:    3
            glyph:   "󱕃"
            title:   root.picked ? root.picked.label : Translation.tr("Pick a module")
            subtitle: !root.picked ? Translation.tr("Press one on the bar or sidebar, or in the library")
                    : root.pickedWhere === "bar"  ? Translation.tr("On the bar")
                    : root.pickedWhere === "side" ? Translation.tr("On the sidebar")
                    :                               Translation.tr("Not placed")
            accent:  Colors.of(QsWindow.window).primary

            actions: PanelButton {
                capsule: true
                visible: inspector.customised
                label:   Translation.tr("Reset")
                symbol:  "restart_alt"
                variant: "ghost"
                onActivated: inspector.reset()
            }

            ModuleInspector {
                id: inspector
                moduleId: UiState.barInspectModule
            }
        }

        // ══ Everything ════════════════════════════════════════════════════════
        Section {
            span:    3
            glyph:   "󰮐"
            title:   Translation.tr("Library")
            subtitle: Catalogue.MODULES.length + " modules"
            help:    Translation.tr("Every module, by kind. Click one to see it above, press Add to put it where it belongs, or drag it onto the bar or the sidebar. Drop a module here to take it off.")
            accent:  Colors.of(QsWindow.window).primary

            ModuleLibrary {
                Layout.fillWidth: true
                componentFor: previewModules.componentFor
            }
        }
    }
}
