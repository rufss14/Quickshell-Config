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
// Two groups, and the REAL bar and sidebar above them:
//   the surfaces  armed by the Arrange button (UiState.arrange): press a module on the
//                 bar or the sidebar to pick it, drag it along a surface, across to the
//                 other, or down onto the library to take it off.
//   (the module)  its inspector (ModuleInspector): where it stands, its colour, its
//                 switches, and for the dock and Stats their own settings.
//   Library       everything, on shelves (ModuleLibrary) — what replaced the "Not on
//                 the bar" card.
//
// The file keeps its name (BarPage.qml) so every link to "Bar › Modules" — the desktop
// entry, the search index, remembered pages — still lands here.
//
// ── Arranging is the Arrange button's ────────────────────────────────────────
// Opening the page does not arm it: arming closes every panel, dims the desktop and covers
// the bar in drop targets, which is unwanted when the page is only being read. Done turns
// it off early; leaving the page always disarms, so it can't be left on by switching
// views, closing the window or a reload.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    PreviewModules { id: previewModules }

    // ── Live counts, not a description ────────────────────────────────────────
    readonly property int barCount: {
        let n = 0
        for (const r of Config.regionIds) for (const g of (Config.layout[r] ?? [])) n += g.length
        return n
    }
    readonly property int sideCount: {
        let n = 0
        for (const r of Config.sidebarRegionIds) for (const g of (Config.sidebarLayout[r] ?? [])) n += g.length
        return n
    }

    Component.onDestruction: UiState.arrange = false

    // Open on something rather than an empty "pick one" card: the first module on the
    // bar, unless one is already picked.
    Component.onCompleted: {
        if (UiState.barInspectModule !== "") return
        for (const region of Config.regionIds)
            for (const g of (Config.layout[region] ?? []))
                if (g.length > 0) { UiState.inspectBarModule(g[0]); return }
    }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰍜"
        title:     Translation.tr("Modules")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  Translation.tr("%1 on the bar  ·  %2 on the sidebar").arg(root.barCount).arg(root.sideCount)

        actions: ChipTray {
            ChipButton {
                label:  UiState.arrange ? Translation.tr("Done") : Translation.tr("Arrange")
                symbol: UiState.arrange ? "check" : "drag_pan"
                on:     UiState.arrange
                tint:   Colors.of(QsWindow.window).primary
                onActivated: UiState.arrange = !UiState.arrange
            }
        }

        // ══ The selected one ══════════════════════════════════════════════════
        // Two grouped Sections side by side (its name is the first one's title). One cell of the
        // page, so the page's columns never split them.
        ModuleInspector {
            id: inspector
            moduleId: UiState.barInspectModule
        }

        // ══ Everything ════════════════════════════════════════════════════════
        // A tool body (the shelves) as one segment of a grouped Section.
        Section {
            grouped:  true
            fullRow:  true
            symbol:   "widgets"
            title:    Translation.tr("Library")
            subtitle: Translation.tr("%1 modules").arg(Catalogue.MODULES.length)
            help:     Translation.tr("Every module, by kind. Click one to see it above, press Add to put it where it belongs, or drag it onto the bar or the sidebar. Drop a module here to take it off.")

            ModuleLibrary {
                Layout.fillWidth: true
                componentFor: previewModules.componentFor
            }
        }
    }
}
