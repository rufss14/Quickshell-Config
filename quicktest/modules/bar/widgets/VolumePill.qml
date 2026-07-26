import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── VolumePill ────────────────────────────────────────────────────────────────
// Speaker glyph + level. Left-click opens the mixer panel, scroll adjusts,
// right-click expands an inline slider.
//
// Was EqualizerButton. It polled `sh -c wpctl get-volume` every 2 seconds and
// spawned another `wpctl set-volume` on every single scroll tick and every drag
// frame — and, because the bar built both its layouts, all of that ran twice.
// The level shown could be up to 2s stale, which is why it used to visibly lag
// behind the volume keys.
//
// Now it reads Audio (native PipeWire, pushed) and writes by assigning a
// property. No process, no poll, no debounce, and the number is always current.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.focus

    property bool active: false
    // ── expanded: local by default, persisted on request ────────────────
    // Right-click toggles this. Transient unless the module is opted into
    // "remember" (Settings → Bar → this module), in which case Config holds it and
    // it survives a reload.
    //
    // `_persist` is read once at construction rather than bound, on purpose. If it
    // were a live binding, turning "remember" on in settings would yank the value
    // out from under a state you'd just set by hand — the setting is about what
    // happens NEXT, not a retroactive rewrite of what's on screen.
    property bool expanded: Config.modulePersist("volume")
        ? Config.moduleRightState("volume")
        : false

    function _toggleExpanded() {
        const next = !root.expanded
        if (Config.modulePersist("volume")) Config.setModuleRightState("volume", next)
        // Assigning here would destroy the declarative binding above for good, so an
        // opted-in module would stop tracking Config after its first right-click.
        // Re-establishing it keeps Config the source of truth.
        root.expanded = Qt.binding(() => Config.modulePersist("volume")
            ? Config.moduleRightState("volume")
            : next)
    }

    signal toggled()

    readonly property real volume: Audio.volume
    readonly property bool muted:  Audio.muted

    implicitWidth:  pill.width
    implicitHeight: Tokens.pillHeight

    IconButton {
        id: pill
        height: Tokens.pillHeight
        width:  root.expanded ? expandedW : collapsedW

        readonly property int gap:     Tokens.spacingMd
        readonly property int glyphW:  glyphMeasure.implicitWidth
        readonly property int levelW:  levelMeasure.implicitWidth
        readonly property int sliderW: 80

        readonly property int collapsedW: Tokens.pillPadding + glyphW + gap + levelW + Tokens.pillPadding
        readonly property int expandedW:  Tokens.pillPadding + glyphW + gap + sliderW + gap
                                        + levelMeasure.implicitWidth + Tokens.pillPadding

        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        // The pill's own click/scroll only applies while collapsed — once the
        // slider is out, the slider owns the pointer and only the glyph end
        // stays clickable (see iconHit below).
        interactive: !root.expanded

        onClicked:      root.toggled()
        onRightClicked: root._toggleExpanded()
        onScrolled:     function(d) { Audio.stepVolume(d * 0.05) }

        // Hidden measures — keep the pill's width stable rather than letting it
        // twitch as the percentage changes width between e.g. "9%" and "100%".
        StyledText {
            id: glyphMeasure
            visible: false
            text: "󰕾"
            variant: "title"
            sizeScale: Config.barIconScale
        }
        StyledText {
            id: levelMeasure
            visible: false
            text: "100%"
            variant: "caption"
            sizeScale: Config.barFontScale
            font.bold: true
        }

        // ── Collapsed: glyph + level ──────────────────────────────────────────
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     Tokens.pillPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.expanded ? 0.0 : 1.0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:    Audio.glyph(root.volume, root.muted)
                variant: "title"
                sizeScale: Config.barIconScale
                color:   root.muted ? Colors.danger
                       : root.active ? Colors.stateActiveFg
                       : root.accent
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:      root.muted ? "muted" : Math.round(root.volume * 100) + "%"
                variant:   "caption"
                sizeScale: Config.barFontScale
                font.bold: true
                color:     root.muted ? Colors.warning : Colors.fgMuted
            }
        }

        // ── Expanded: glyph + slider + level ──────────────────────────────────
        Row {
            anchors.left:           parent.left
            anchors.leftMargin:     Tokens.pillPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.gap
            opacity: root.expanded ? 1.0 : 0.0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:    Audio.glyph(root.volume, root.muted)
                variant: "title"
                sizeScale: Config.barIconScale
                color:   root.muted ? Colors.danger : root.accent
            }

            ValueSlider {
                anchors.verticalCenter: parent.verticalCenter
                width:  pill.sliderW
                value:  root.volume
                onMoved:    function(v) { Audio.setVolume(v) }
                onScrolled: function(d) { Audio.stepVolume(d * 0.05) }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width:     levelMeasure.implicitWidth
                text:      root.muted ? "mut" : Math.round(root.volume * 100) + "%"
                variant:   "caption"
                sizeScale: Config.barFontScale
                font.bold: true
                emphasis:  "dim"
            }
        }

        // While expanded, keep the glyph end clickable so the panel and the
        // mute toggle stay reachable without collapsing the slider first.
        MouseArea {
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            width:          Tokens.pillPadding + pill.glyphW
            visible:        root.expanded
            hoverEnabled:   true
            cursorShape:    Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: function(m) {
                if (m.button === Qt.RightButton)       root.expanded = false
                else if (m.button === Qt.MiddleButton) Audio.toggleMute()
                else                                   root.toggled()
            }
            onWheel: function(w) { Audio.stepVolume(w.angleDelta.y > 0 ? 0.05 : -0.05) }
        }
    }
}
