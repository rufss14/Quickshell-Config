import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// One thumbnail in the grid. What an entry IS and what a click does to it live in
// WallpaperEntry (shared with the list row); this file is only how the tile looks.
Item {
    id: tile
    required property var panel
    // Handed in by the gallery's model (Bound delegates take them as required properties).
    required property var modelData
    required property int index
    readonly property var entry: tile.modelData

    // The keyboard's cursor is on this tile (WallpaperPanel.kbIndex): an outline, not a fill.
    readonly property bool kbFocused: panel.kbOn && panel.kbIndex === tile.index

    WallpaperEntry { id: st; panel: tile.panel; entry: tile.entry }

    // Which workspaces own this picture (per-workspace mode). Empty when it is on
    // every one of them — the "applied" mark already says that.
    readonly property var owners: {
        if (st.isAction || !Wallpaper.perWorkspace) return []
        const o = []
        for (let n = 1; n <= Wallpaper.pickable; n++)
            if (Wallpaper.wallFor(n) === st.value) o.push(n)
        return o.length < Wallpaper.pickable ? o : []
    }

    // ── The entrance, and the lean ────────────────────────────────────────
    // A tile arrives calmly — a critically damped spring (no overshoot) from 0.94, fading in — a few beats after
    // its neighbours — `slot` is its place in the grid, capped so a long scroll doesn't queue
    // — and leans toward the pointer / dips on a press on another. Springs, not eased tweens:
    // the same feel as the media panel's controls.
    readonly property int slot: tile.index
    // 0 → 1 as the tile arrives (effects spring, ζ = 1: it settles without bouncing); `target` is
    // set when its turn in the stagger comes. SpringValue is frame-exact, unlike SpringAnimation,
    // which steps at 16 ms and stair-steps on a 165 Hz screen.
    SpringValue {
        id: arrival
        target: Config.motionEnabled ? 0 : 1
        spec: Motion.springEffectsSlow
    }
    readonly property real arrive: arrival.value
    Timer {
        running: Config.motionEnabled
        interval: Math.min(tile.slot, 8) * Motion.stagger * 1.25
        onTriggered: arrival.target = 1
    }
    opacity: Math.min(1, Math.max(0, tile.arrive) * 1.6)

    SpringValue {
        id: leanSpring
        target: press.pressed ? 0.95 : hover.hovered ? 1.04 : 1.0
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    readonly property real lean: leanSpring.value

    // ── The picture's corner is a shape that answers ──────────────────────
    // Rounder under the pointer and while it is ticked, on a spring (Material 3 Expressive: state
    // changes reshape, they don't only recolour). The frame's corner stays concentric with it.
    SpringValue {
        id: shapeK
        target: (hover.hovered || st.selected) ? 1 : 0
        spec: Motion.springSpatial
        epsilon: 0.002
    }
    readonly property real picRadius: Tokens.radiusCard + Math.max(0, shapeK.value) * Tokens.spacingSm

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: Tokens.spacingSm
        // Transparent at rest — the picture is the box. The wallpaper on show, and a ticked one, sit
        // in a TONAL frame (primaryContainer: the picture's own tile, lit from the accent), where the
        // old grid drew a 2px ring. Hover is the state layer below, not a second tint. The action
        // card keeps its own ground.
        color: st.removeLatch.armed ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.18)
             : (st.selected || st.isCurrent) ? Colors.of(QsWindow.window).primaryContainer
             : "transparent"
        // Concentric with the picture inside it (its radius + the margin between).
        radius: tile.picRadius + Tokens.spacingXs
        clip: true

        Behavior on color { ColorAnimation { duration: Motion.respond } }

        // Workspace owners keep a faint outline (the "showing now" mark is the frame and the tick).
        border.width: tile.owners.length > 0 ? Tokens.borderWidth : 0
        border.color: st.removeLatch.armed ? Colors.of(QsWindow.window).danger
                    : tile.owners.length > 0 ? Colors.of(QsWindow.window).alpha(panel.accent, 0.35)
                    : "transparent"
        scale: tile.lean * (0.94 + 0.06 * Math.max(0, tile.arrive))

        Behavior on border.color { ColorAnimation  { duration: Motion.respond } }

        StateLayer {
            id: feel
            anchors.fill: parent
            radius: frame.radius
            hovered: hover.hovered
            layerColor: panel.accent
        }

        // The keyboard cursor (arrows, Home/End, PageUp/PageDown move it; Enter applies).
        Rectangle {
            anchors.fill: parent
            radius: frame.radius
            color: "transparent"
            border.width: 2
            border.color: Colors.of(QsWindow.window).focus
            opacity: tile.kbFocused ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        // ── The action card ───────────────────────────────────────────────
        // Deliberately the SAME anatomy as a wallpaper tile: an inset panel
        // where the picture would be, and the name on its own underneath. The
        // inset's edge is what separates the two, exactly as it does on every
        // other tile — a card that invented its own shape read as a different
        // kind of object rather than the first item in the same gallery. Its
        // fill is the raised one and the card behind it the panel's own
        // background, so the inset reads as the object and the card as its frame.
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingXs
            spacing: Tokens.spacingXs
            visible: st.isAction

            Rectangle {
                id: slot
                Layout.fillWidth:  true
                Layout.fillHeight: true
                // An EMPTY slot: the picture's own shape with a dashed outline and a faint fill, so it
                // reads as "a picture goes here" rather than as a button of another kind.
                color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
                radius: tile.picRadius
                clip: true

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Colors.of(QsWindow.window).alpha(hover.hovered ? panel.accent : Colors.of(QsWindow.window).fg, hover.hovered ? 0.8 : 0.28)
                        fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 3]
                        Behavior on strokeColor { ColorAnimation { duration: Motion.respond } }
                        PathRectangle {
                            x: 1; y: 1
                            width: slot.width - 2; height: slot.height - 2
                            radius: Math.max(0, tile.picRadius - 1)
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.spacingMd * 2
                    spacing: Tokens.spacingXs

                    // The action's icon in a cookie that winds when the card is pointed at.
                    ScallopChip {
                        Layout.alignment: Qt.AlignHCenter
                        glyph: st.isAction ? tile.entry.glyph : ""
                        tint:  Colors.of(QsWindow.window).focus
                        hot:   hover.hovered
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: st.isAction ? tile.entry.caption : ""
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                Layout.leftMargin: Tokens.spacingMd
                verticalAlignment: Text.AlignVCenter
                text: st.name
                variant: "caption"
                color: hover.hovered ? panel.accent : Colors.of(QsWindow.window).fgMuted
                Behavior on color { ColorAnimation { duration: Motion.respond } }
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
            }
        }

        // ── A wallpaper ───────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingXs
            spacing: Tokens.spacingXs
            visible: !st.isAction

            ClippingRectangle {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)
                radius: tile.picRadius

                // Loading plate: calm. A soft tint breathing slowly, with one small cookie turning in the
                // middle — in place of a bar of light sweeping across (which read as busy) and a
                // spinner on top of it. When the picture decodes it fades in over the plate and
                // settles from a touch larger, so it arrives rather than appears.
                // (The animations below name `loadingPlate` rather than `parent`: inside an animation object
                // `parent` is null — it is not an item — and every `parent.visible` here threw a TypeError
                // each time it was read, which is how the live log filled with ~200 of them and none of
                // these ran.)
                Item {
                    id: loadingPlate
                    anchors.fill: parent
                    visible: thumbImage.status !== Image.Ready

                    Rectangle {
                        anchors.fill: parent
                        color: Colors.of(QsWindow.window).alpha(panel.accent, 0.08)
                        SequentialAnimation on opacity {
                            running: loadingPlate.visible && Config.motionEnabled
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: Motion.slow * 2; easing.type: Motion.ambient }
                            NumberAnimation { to: 1.0;  duration: Motion.slow * 2; easing.type: Motion.ambient }
                        }
                    }
                    Scallop {
                        anchors.centerIn: parent
                        width:  Tokens.iconXl
                        height: Tokens.iconXl
                        points: 8
                        petalDepth: 0.2
                        fillColor: Colors.of(QsWindow.window).alpha(panel.accent, 0.30)
                        NumberAnimation on rotation {
                            from: 0; to: 360; duration: 6000
                            loops: Animation.Infinite
                            running: loadingPlate.visible && Config.motionEnabled
                        }
                        SequentialAnimation on scale {
                            running: loadingPlate.visible && Config.motionEnabled
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.18; duration: Motion.slow * 2; easing.type: Motion.ambient }
                            NumberAnimation { to: 0.86; duration: Motion.slow * 2; easing.type: Motion.ambient }
                        }
                    }
                }
                Image {
                    id: thumbImage
                    anchors.fill: parent
                    opacity: status === Image.Ready ? 1 : 0
                    scale:   status === Image.Ready ? 1 : 1.06
                    Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                    Behavior on scale   { NumberAnimation { duration: Motion.spatialSlow; easing.type: Motion.travel } }
                    source: panel.bust(st.thumb)
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    // Decoded off the UI thread and downscaled at load: these are 4K
                    // files rendered into a 150px cell, and without sourceSize each one
                    // would hold its full decoded size in memory.
                    asynchronous: true
                    cache: true
                    sourceSize.width:  300
                    sourceSize.height: 200
                }

                // ── Scene previews move, but only ONE at a time ────────────
                // Workshop previews are mostly GIFs, and a still frame of an
                // animated wallpaper undersells it. The settings page can
                // afford six playing decoders because it shows six tiles; this
                // grid scrolls a whole library through a 535px panel, so the
                // ceiling here is the tile under the pointer. Everything else
                // is the Image above, which renders a GIF's first frame.
                AnimatedImage {
                    anchors.fill: parent
                    visible: st.isGif && hover.hovered
                    source: visible ? panel.bust(st.thumb) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    playing: visible
                }

                // Bottom-left badges, left to right: "showing now" tick, a scene's
                // play mark, then the workspaces that own it (first three, "+n"
                // after). Clear of the ✕ (top-left) and the star (top-right).
                Row {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: Tokens.spacingXs
                    spacing: Tokens.spacingXs

                    // The "showing now" tick on a little cookie (the redesign's shape), not a
                    // plain disc.
                    Item {
                        width:  Tokens.iconMd + 4
                        height: Tokens.iconMd + 4
                        visible: st.isCurrent

                        Scallop {
                            anchors.fill: parent
                            points: 8
                            petalDepth: 0.16
                            fillColor: panel.accent
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "check"
                            fill: 1
                            color: Colors.of(QsWindow.window).fgOnPrimary
                            variant: "caption"
                        }
                    }
                    Rectangle {
                        width:  Tokens.iconMd
                        height: Tokens.iconMd
                        radius: width / 2
                        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                        visible: st.isScene

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "play_arrow"
                            fill: 1
                            color: panel.accent
                            variant: "micro"
                        }
                    }
                    Repeater {
                        model: tile.owners.slice(0, 3).concat(tile.owners.length > 3 ? [-(tile.owners.length - 3)] : [])
                        delegate: Rectangle {
                            id: chip
                            required property int modelData
                            width:  Math.max(Tokens.iconMd, chipText.implicitWidth + Tokens.spacingSm)
                            height: Tokens.iconMd
                            radius: height / 2
                            color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                            border.width: Tokens.borderWidth
                            border.color: Colors.of(QsWindow.window).alpha(panel.accent, 0.6)

                            StyledText {
                                id: chipText
                                anchors.centerIn: parent
                                text: chip.modelData < 0 ? "+" + (-chip.modelData) : String(chip.modelData)
                                variant: "micro"
                                color: panel.accent
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // ── Where the bin and the star went ───────────────────────────────
                // They used to float over the picture's two top corners, covering it and fighting the
                // apply pill. They live in the CAPTION now (below the picture, beside the name), so the
                // picture stays a picture: the star is always there once it is lit and appears on hover
                // otherwise; the bin appears on hover and ARMS on the first press, growing into a red
                // "Remove?" pill with a bar draining over the arm (ArmLatch's timeout) — the second
                // press does it. The sentence over the picture says what the second press will do,
                // because "delete" and "delete and unsubscribe" are not the same promise.
                //   • delete_forever for a scene (its files really go); the plain bin for an image,
                //     which only moves to the trash.

                // The tick, top-left, in select mode.
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: Tokens.spacingSm
                    width:  Tokens.iconXl + Tokens.spacingXs
                    height: width
                    radius: width / 2
                    visible: panel.selecting && !st.isAction
                    color: st.selected ? panel.accent
                                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.92)
                    border.width: st.selected ? 0 : Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outline
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "check"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        opacity: st.selected ? 1 : 0
                        color: Colors.of(QsWindow.window).fgOnPrimary
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }

                // ── Customise: the tune glyph, bottom-right ────────────────
                // Scenes only. Bottom-left is taken by the "current" mark.
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: Tokens.spacingXs
                    width:  Tokens.iconMd
                    height: Tokens.iconMd
                    radius: width / 2
                    visible: st.isScene
                    color:  panel.accent
                    opacity: hover.hovered && !panel.selecting ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "equalizer"
                        variant: "micro"
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.openProperties(st.key)
                    }
                }

                // ── Apply ─────────────────────────────────────────────────────────
                // The whole tile is still clickable, but "click the picture" is a convention
                // you have to already know. A named button on hover says what the click DOES,
                // where you're already looking. It pops in on a spring (rising a few pixels as
                // it grows), and stays up while the apply it kicked is in flight, whether or
                // not the pointer is still on the tile. Applying, its icon turns into a small
                // cookie spinning in its place, the pill breathes and a ring pulses off it.
                Rectangle {
                    id: applyPill
                    readonly property bool shown: panel.selecting ? false
                        : panel.pickingActive
                        ? (hover.hovered && st.isScene && !st.removeLatch.armed)
                        : ((hover.hovered || st.busy) && !st.applied && !st.removeLatch.armed)

                    anchors.centerIn: parent
                    width:  applyRow.implicitWidth + Tokens.spacingLg * 2
                    height: Tokens.iconXl + Tokens.spacingSm
                    radius: height / 2
                    color:  panel.accent
                    opacity: applyPill.shown ? 1 : 0
                    visible: opacity > 0.005
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    Behavior on width   { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                    // The pop: grows from 0.72 with a little overshoot, rising as it does.
                    SpringValue {
                        id: applyPop
                        target: applyPill.shown ? 1 : 0
                        spec: Motion.springSpatialFast
                    }
                    readonly property real pop: Math.max(0, applyPop.value)
                    // The breath while applying.
                    property real breath: 1
                    SequentialAnimation {
                        running: st.busy && applyPill.visible && Config.motionEnabled
                        loops: Animation.Infinite
                        NumberAnimation { target: applyPill; property: "breath"; to: 1.05; duration: Motion.pulse; easing.type: Motion.ambient }
                        NumberAnimation { target: applyPill; property: "breath"; to: 1.0;  duration: Motion.pulse; easing.type: Motion.ambient }
                    }
                    scale: (0.72 + 0.28 * applyPill.pop) * (st.busy ? applyPill.breath : 1.0)
                    transform: Translate { y: (1 - applyPill.pop) * 8 }

                    // A ring that breathes out while working.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: panel.accent
                        visible: st.busy
                        SequentialAnimation on opacity {
                            running: st.busy && applyPill.visible && Config.motionEnabled
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.5; to: 0.0; duration: Motion.pulse; easing.type: Motion.travel }
                            NumberAnimation { from: 0.0; to: 0.5; duration: 1 }
                        }
                    }

                    Row {
                        id: applyRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingSm

                        // The icon slot: the action's icon, swapped for a turning cookie while busy.
                        Item {
                            width:  Tokens.iconMd
                            height: Tokens.iconMd
                            anchors.verticalCenter: parent.verticalCenter

                            MaterialIcon {
                                anchors.centerIn: parent
                                name: panel.pickingActive ? "add" : "wallpaper"
                                fill: 1
                                font.pixelSize: Tokens.iconMd
                                color: Colors.of(QsWindow.window).fgOnPrimary
                                opacity: st.busy ? 0 : 1
                                scale:   st.busy ? 0.3 : 1
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                            }
                            Scallop {
                                anchors.fill: parent
                                points: 8
                                petalDepth: 0.22
                                fillColor: Colors.of(QsWindow.window).fgOnPrimary
                                opacity: st.busy ? 1 : 0
                                scale:   st.busy ? 1 : 0.3
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                NumberAnimation on rotation {
                                    from: 0; to: 360; duration: 1400
                                    loops: Animation.Infinite
                                    running: st.busy && applyPill.visible && Config.motionEnabled
                                }
                            }
                        }
                        StyledText {
                            id: applyLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.pickingActive ? "Assign"
                                : st.busy ? "Applying…" : "Apply"
                            color: Colors.of(QsWindow.window).fgOnPrimary
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // What the second ✕ will actually do. Named, because "delete" and
                // "delete and unsubscribe" are not the same promise.
                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.spacingMd * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    color: Colors.of(QsWindow.window).danger
                    font.weight: Font.DemiBold
                    visible: st.removeLatch.armed
                    text: st.isScene
                        ? (WallpaperEngine.stillSubscribed(st.key)
                            ? "Steam put it back: still subscribed. Press again, then Unsubscribe on its page"
                            : "Press the bin again: delete + unsubscribe")
                        : "Press the bin again: move to trash"
                }
            }

            // ── The caption: the name, and what you do to it ──────────────────────────
            // While it is the wallpaper (or ticked) the tonal frame carries the state, so the name sits on
            // it in the container's own text colour. The action card has only its name, centred.
            RowLayout {
                id: caption
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                Layout.leftMargin: Tokens.spacingMd
                Layout.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingXs

                readonly property color ink: (st.isCurrent || st.selected) ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                                            : Colors.of(QsWindow.window).fgMuted

                StyledText {
                    id: nameText
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: st.name
                    variant: "caption"
                    font.weight: st.isCurrent ? Font.DemiBold : Font.Normal
                    color: caption.ink
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    horizontalAlignment: st.isAction ? Text.AlignHCenter : Text.AlignLeft
                    elide: Text.ElideMiddle
                }

                // ── The star ──────────────────────────────────────────────────────────
                // Lit (warning gold, filled) it is always shown — that is how a favourite reads in the
                // grid; unlit it is an outline that appears on hover. A toggle bumps.
                Item {
                    id: favBtn
                    visible: !st.isAction
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth:  Tokens.iconLg
                    Layout.preferredHeight: Tokens.iconLg
                    readonly property bool shown: !panel.selecting && !st.removeLatch.armed && (hover.hovered || st.isFav)
                    opacity: favBtn.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, favMouse.containsMouse ? Tokens.stateHover : 0)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    SpringValue {
                        id: favDip
                        target: favMouse.pressed ? 0.82 : 1.0
                        spec: Motion.springSpatialFast
                        epsilon: 0.002
                    }
                    property real bump: 1
                    scale: favDip.value * favBtn.bump
                    Connections {
                        target: st
                        function onIsFavChanged() { favBump.restart() }
                    }
                    SequentialAnimation {
                        id: favBump
                        NumberAnimation { target: favBtn; property: "bump"; to: 1.35; duration: Motion.respond; easing.type: Motion.travel }
                        NumberAnimation { target: favBtn; property: "bump"; to: 1.0; duration: Motion.standard; easing.type: Motion.overshoot }
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "star"
                        fill: st.isFav ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: st.isFav ? Colors.of(QsWindow.window).warning : caption.ink
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    MouseArea {
                        id: favMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.toggleFav()
                    }
                }

                // ── The bin ───────────────────────────────────────────────────────────
                Item {
                    id: delBtn
                    visible: !st.isAction
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: Tokens.iconLg
                    Layout.preferredWidth: delW.value
                    readonly property bool armed: st.removeLatch.armed
                    readonly property bool shown: !panel.selecting && (hover.hovered || delBtn.armed)
                    opacity: delBtn.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                    // Armed, it stretches into the "Remove?" pill.
                    SpringValue {
                        id: delW
                        target: delBtn.armed ? delRow.implicitWidth + Tokens.spacingMd * 2 : Tokens.iconLg
                        spec: Motion.springSpatialFast
                        epsilon: 0.1
                    }
                    SpringValue {
                        id: delDip
                        target: delMouse.pressed ? 0.9 : 1.0
                        spec: Motion.springSpatialFast
                        epsilon: 0.002
                    }
                    scale: delDip.value

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: delBtn.armed ? Colors.of(QsWindow.window).danger
                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, delMouse.containsMouse ? Tokens.stateHover : 0)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    Row {
                        id: delRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: st.isScene ? "delete_forever" : "delete"
                            fill: delBtn.armed ? 1 : 0
                            font.pixelSize: Tokens.iconMd
                            color: delBtn.armed ? Colors.of(QsWindow.window).fgOnPrimary : caption.ink
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: delBtn.armed
                            text: Translation.tr("Remove?")
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: Colors.of(QsWindow.window).fgOnPrimary
                        }
                    }
                    // The arm's countdown.
                    property real drain: 1
                    NumberAnimation {
                        id: drainAnim
                        target: delBtn
                        property: "drain"
                        from: 1; to: 0
                        duration: st.removeLatch.timeoutMs
                        easing.type: Easing.Linear
                    }
                    onArmedChanged: if (delBtn.armed) drainAnim.restart(); else drainAnim.stop()
                    Rectangle {
                        visible: delBtn.armed
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.spacingXs
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 2
                        radius: 1
                        width: (parent.width - Tokens.spacingMd * 2) * delBtn.drain
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimary, 0.7)
                    }
                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.doRemove()
                    }
                }
            }
        }

        // ── Hover is a HANDLER, the click is a MouseArea behind ───────────
        // The ✕ has its own MouseArea, and a MouseArea does not propagate hover:
        // pointing at the ✕ would take `containsMouse` away from the tile's own
        // area, and since the ✕ is only visible on hover it would vanish from
        // under the pointer. A HoverHandler keeps reporting through it. The
        // click MouseArea then sits at z: -1 so the ✕ wins its own 20px.
        HoverHandler {
            id: hover
            onHoveredChanged: if (!hovered) st.removeLatch.disarm()
        }
        MouseArea {
            id: press
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Picking is a Config-only write — it doesn't touch applyBusy or
            // the theming pipeline, so it isn't gated by them like a real apply.
            enabled: panel.selecting || panel.pickingActive
                ? true
                : (st.isAction || (!panel.applyBusy && panel.blocked === ""))
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: function (m) { feel.press(m.x, m.y) }
            onReleased: feel.release()
            onCanceled: feel.release()
            onClicked: function (m) { if (m.button === Qt.RightButton) st.doChoose(); else st.doApply() }
            z: -1
        }
    }
}
