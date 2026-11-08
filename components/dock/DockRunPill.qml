pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs
import "../../services/workspaces.js" as Wsp
import ".."
import "."

// DockRunPill — DockIconStrip's inline `RunPill`, moved into its own file (2026-11-08).
// ── One slot's share of the inner pill ────────────────────────────────────
// One per app, over the same ScriptModel as the buttons, so these live as long
// as their buttons do. The model is NOT the list of runs: the workspaces pill
// learned that a fresh array of runs rebuilds every pill on every change (it
// "refreshes the whole pill"). Here each slot asks whether a run STARTS at it
// and how long; a slot that stops being a head fades out while its neighbour's
// grows over it, so two runs joining read as one pill reaching over the other.
//
// The bar's inner pill, as a recipe: a nested (lighter) surface, no border, no
// shadow. Out of the way during a drag, where positions are in flux.
Surface {
    id: pill
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip
    required property int index
    required property string modelData

    readonly property int  len:  strip.runLengths[pill.index] ?? 0
    readonly property bool head: pill.len > 0

    property real start: strip.slotPos(pill.index)
    // To the run's last button wherever it stands (a run can cross the pin gap).
    property real span:  pill.len > 0 ? Math.max(0, strip.slotPos(pill.index + pill.len - 1) + strip.button - pill.start) : 0
    Behavior on start { NumberAnimation { duration: Motion.emphasized
                        easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
    Behavior on span  { NumberAnimation { duration: Motion.emphasized
                        easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }

    x: strip.vertical ? 0 : pill.start
    y: strip.vertical ? pill.start : 0
    width:  strip.vertical ? strip.button : pill.span
    height: strip.vertical ? pill.span : strip.button

    // One step up with the bar's feedback: the sidebar draws its own inner pill
    // round the whole dock at Nested, and a run pill at Nested on it would vanish.
    elevation:    strip.barFeedback ? Tokens.elevationPopup : Tokens.elevationNested
    cornerRadius: strip.cellRadius
    borderWidth:  0
    castsShadow:  false
    itemOpacity:  Config.dockInnerPill && pill.head && strip.dragKey === "" && strip.insertAt < 0 ? 1 : 0
    visible: pill.opacity > 0.01
    Behavior on itemOpacity { NumberAnimation { duration: Motion.standard } }
}
