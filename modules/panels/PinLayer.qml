pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"

// ── PinLayer ──────────────────────────────────────────────────────────────────
// One screen's pinned pictures (services/SnipPins): a window over the whole screen that exists
// only while this screen has a pin, and takes input ONLY on the cards — the mask is one Region
// per pin, from the pin's record, so the desktop under everything else keeps its clicks.
//
// Built on the pattern WidgetLayer documents: the regions come from the MODEL (not from the
// cards, which may not exist yet) and the list is rebuilt from the Instantiator's own add/remove
// signals. An empty mask means "input nowhere", which is what an unmapped layer wants.
//
// No keyboard: a pin never takes focus off what you are working in. It closes with its ✕ or a
// right-click, and `qs ipc call pins closeAll` clears the lot.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: layer

    // From modelData, never the window's own `screen` (that would loop through map/unmap).
    required property string screenName

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-pins-" + screenName.replace(/[^A-Za-z0-9._-]/g, "_")
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true
    color: "transparent"

    // This screen's pin ids. Reassigned only when the SET changes: a drag rewrites a pin's
    // record on every pointer move, and a model that were rebuilt each time would destroy the
    // card being dragged under the pointer.
    property var ids: []
    function _sync() {
        const next = SnipPins.items.filter(p => p.screen === layer.screenName).map(p => p.id)
        if (JSON.stringify(next) !== JSON.stringify(layer.ids)) layer.ids = next
    }
    Component.onCompleted: layer._sync()
    Connections {
        target: SnipPins
        function onItemsChanged() { layer._sync() }
    }
    visible: layer.ids.length > 0

    mask: Region { id: passthrough; regions: layer._maskRegions }
    property var _maskRegions: []
    function _rebuildMask() {
        const out = []
        for (let i = 0; i < regionMaker.count; i++) {
            const r = regionMaker.objectAt(i)
            if (r) out.push(r)
        }
        layer._maskRegions = out
    }
    Instantiator {
        id: regionMaker
        model: layer.ids
        onObjectAdded:   layer._rebuildMask()
        onObjectRemoved: layer._rebuildMask()
        delegate: Region {
            id: region
            required property string modelData
            readonly property var rec: SnipPins.get(region.modelData)
            x:      region.rec ? region.rec.x : 0
            y:      region.rec ? region.rec.y : 0
            width:  region.rec ? region.rec.w : 0
            height: region.rec ? region.rec.h : 0
            radius: Tokens.radiusSm
        }
    }

    Repeater {
        model: layer.ids
        PinCard {
            required property string modelData
            pinId: modelData
            bounds: Qt.size(layer.width, layer.height)
        }
    }
}
