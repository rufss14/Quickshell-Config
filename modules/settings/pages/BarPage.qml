pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../state"
import ".."
import "../../../services"

// ── BarPage — Bar › Modules ───────────────────────────────────────────────────
// What is on your bar, what isn't, and what the selected one does.
//
// ── It was one page pretending to be three ────────────────────────────────────
// This file used to be the whole Bar section: its own PanelHeader, its own
// Modules|Style segmented strip, and two Flickables — both built, both alive, one
// faded to zero. That predates the rail having view strips of its own, so the page
// carried a second strip under the first, and the Style grid was mounted the entire
// time you were arranging modules.
//
// It is three views now, which the rail switches between: Modules (this file),
// Style (BarStylePage) and Panels (BarPanelsPage). Only the one you are looking at
// exists. Nothing here draws its own header or its own strip.
//
// ── No preview, because the bar isn't a preview away ──────────────────────────
// A scaled-down picture of the bar lived at the top of this page once
// (`BarPreview`, off `Config.layout`). It was accurate and it was redundant: the
// REAL bar is a few pixels above this window, at full brightness, in arrange mode
// — a second, smaller copy of the thing you can already see answered a question
// nobody was asking. Removed, and the width it held goes to the catalogue and the
// inspector, which are what this page is actually for.
//
// ── Two cards ─────────────────────────────────────────────────────────────────
// What isn't on the bar, and the module you picked. "Anchor on workspaces" used to sit
// between them as a lone tile; it is about the whole bar's centring, so it lives with
// the bar's other switches in Bar › Style.
//
// ── Arrange mode is the button's, not the page's ─────────────────────────────
// It used to arm itself when this page opened (and the bar was then covered in drop
// targets whether or not you wanted to move anything). Now the header's Arrange button
// is the only way in. Leaving the page still disarms it, so it can't be left on by
// switching views, closing the window or a reload.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    PreviewModules { id: previewModules }

    // ── A live reading, not a description ─────────────────────────────────────
    // `layout` is region → groups → ids, so a count means flattening. Cheap, and it
    // is the one number that says whether the thing you just dragged landed.
    function _count(region) {
        const groups = Config.layout[region] ?? []
        let n = 0
        for (let i = 0; i < groups.length; i++) n += groups[i].length
        return n
    }

    // Opening the page does NOT arm arrange mode (the header button does); closing it
    // always disarms, so it can't stay on.
    Component.onDestruction: UiState.barArrange = false

    // Open on something rather than an empty "pick one" card: the first module on the
    // bar, unless one is already picked.
    Component.onCompleted: {
        if (UiState.barInspectModule !== "") return
        for (const region of ["left", "centre", "right"])
            for (const g of (Config.layout[region] ?? []))
                if (g.length > 0) { UiState.inspectBarModule(g[0]); return }
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰍜"
        title:     Translation.tr("Bar")
        titleTail: "modules"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root._count("left") + " left  ·  " + root._count("centre")
                   + " centre  ·  " + root._count("right") + " right"

        actions: ChipTray {
            ChipButton {
                label:  UiState.barArrange ? "Done" : "Arrange"
                symbol: UiState.barArrange ? "check" : "drag_pan"
                on:     UiState.barArrange
                tint:   Colors.of(QsWindow.window).primary
                onActivated: UiState.barArrange = !UiState.barArrange
            }
        }

        // ══ Your bar ══════════════════════════════════════════════════════════
        // The real widgets in their real groups, small — and the way to pick one.
        Section {
            span:     3
            glyph:    "󰍜"
            title:    Translation.tr("Your bar")
            subtitle: Translation.tr("Click a module to change it")
            help:     Translation.tr("Your bar, drawn from its own widgets. Click one to edit it below. To move modules between pills, press Arrange and drag them on the real bar.")
            accent:   Colors.of(QsWindow.window).primary

            PreviewStage {
                Layout.fillWidth: true
                Layout.preferredHeight: barMap.implicitHeight + Tokens.spacingLg * 2
                checkered: false

                BarMap {
                    id: barMap
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    componentFor: previewModules.componentFor
                }
            }
        }

        // ══ The selected one ══════════════════════════════════════════════════
        // Its name is the card's title; two columns inside (ModuleInspector).
        Section {
            span:    3
            glyph:   "󱕃"
            title:   inspector.info ? inspector.info.label : "Pick a module"
            subtitle: !inspector.info ? "Click one on the bar above"
                    : inspector.placed ? "On the bar" : "Not on the bar"
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

        // ══ The pool ══════════════════════════════════════════════════════════
        Section {
            span:    3
            glyph:   "󰮐"
            title:   Translation.tr("Not on the bar")
            subtitle: Config.availableModules.length === 0
                ? "Everything is placed"
                : Config.availableModules.length + " waiting"
            help:    Translation.tr("Drag one straight up onto the bar, or click it to drop it somewhere sensible. Drag a module off the bar onto this card to take it off.")
            accent:  Colors.of(QsWindow.window).primary

            ModuleTray {
                Layout.fillWidth: true
                componentFor: previewModules.componentFor
            }
        }
    }
}
