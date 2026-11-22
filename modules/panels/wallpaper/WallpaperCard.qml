pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// ── WallpaperCard ─────────────────────────────────────────────────────────────
// One wallpaper in the island's gallery: the PICTURE is the card. Nothing sits under it; what you
// need about it rides on it, on small surface-toned pills, and only when it matters:
//
//   the name        bottom-left, under the pointer (and always on the one on screen)
//   the tools       top-right, a capsule under the pointer: bookmark, a scene's options, the bin. A
//                   bookmarked one keeps a small mark. The bin lays a confirm over the picture (Keep / Remove)
//                   and frames the card in the danger tone
//   Apply           the middle, under the pointer: a click anywhere on the card applies it
//
// Every picture is mounted on a canvas (a lifted plate with a hairline); the one on screen wears the
// accent as that canvas and a cookie with a tick, and its corner is the hero's: the shape says "this
// one", not a caption. Under the pointer any card takes that corner on a
// spring and leans in.
//
// What a card DOES is WallpaperEntry (the same object the bar's tile and row use: apply, per-workspace
// choice on a right click, star, remove, select, assign to a monitor), so the two galleries cannot
// drift apart in behaviour, only in looks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: card

    required property var panel
    required property var modelData
    required property int index
    readonly property var entry: card.modelData
    readonly property var palette: Colors.of(QsWindow.window)

    readonly property bool kbFocused: panel.kbOn && panel.kbIndex === card.index

    WallpaperEntry { id: st; panel: card.panel; entry: card.entry }

    // Which workspaces wear it, while each can have its own: shown as numbers on the picture. None
    // when it is on all of them.
    readonly property var owners: {
        if (st.isAction || !Wallpaper.perWorkspace) return []
        const o = []
        for (let n = 1; n <= Wallpaper.pickable; n++)
            if (Wallpaper.wallFor(n) === st.value) o.push(n)
        return o.length < Wallpaper.pickable ? o : []
    }

    readonly property bool armed: st.removeLatch.armed
    readonly property bool framed: card.armed || st.isCurrent || st.selected
    readonly property color pill: card.palette.alpha(card.palette.surface, 0.86)

    // ── Motion ────────────────────────────────────────────────────────────────
    PopIn { id: pop; active: true; index: card.index; cap: 9 }
    opacity: pop.opacity

    SpringValue {
        id: lean
        target: press.pressed ? 0.96 : hover.hovered ? 1.03 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    // 0 → 1: the card's corner goes from a card's to the hero's.
    SpringValue {
        id: shapeK
        target: hover.hovered || card.framed ? 1 : 0
        spec: Motion.springSpatial
        epsilon: 0.002
    }
    readonly property real corner: Tokens.radiusCard + Math.max(0, shapeK.value) * (Tokens.radiusXl - Tokens.radiusCard)
    // 0 → 1: the frame round the picture.
    SpringValue {
        id: frameK
        target: card.framed ? 1 : 0
        spec: Motion.springSpatialFast
        epsilon: 0.002
    }
    // The canvas the picture is mounted on: always there, `panel.cardMat` wide, and the frame
    // swells it a touch while the card is the one on screen, selected or armed.
    readonly property real ring: card.panel.cardMat + Math.max(0, frameK.value) * Tokens.spacingXs

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: Tokens.spacingXs
        scale: lean.value * pop.scale

        // The canvas: a lifted tonal plate with a hairline at rest, the accent for the one on screen
        // and a selected one, the danger tone while the bin is armed. The picture is inset by `ring`.
        Rectangle {
            anchors.fill: parent
            visible: !st.isAction
            radius: card.corner
            color: card.armed ? card.palette.danger
                 : card.framed ? card.palette.primary
                 : card.palette.plate
            border.width: Tokens.borderWidth
            border.color: card.framed ? "transparent" : card.palette.outline
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            Behavior on border.color { ColorAnimation { duration: Motion.respond } }
        }

        // ══ An action (add pictures, browse the Workshop…) ════════════════════
        Rectangle {
            anchors.fill: parent
            visible: st.isAction
            radius: card.corner
            color: card.palette.primaryContainer

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingMd * 2
                spacing: Tokens.spacingXs

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Tokens.iconXl + Tokens.spacingLg
                    height: width
                    MorphShape {
                        anchors.fill: parent
                        shape: hover.hovered ? "squircle" : "cookie9"
                        spec: Motion.springSpatialFast
                        fillColor: card.palette.primary
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        glyph: st.isAction ? card.entry.glyph : ""
                        fill: 1
                        font.pixelSize: Tokens.iconLg
                        color: card.palette.fgOnPrimary
                    }
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: st.name
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: card.palette.fgOnPrimaryContainer
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: st.isAction ? card.entry.caption : ""
                    variant: "caption"
                    color: card.palette.alpha(card.palette.fgOnPrimaryContainer, 0.72)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        // ══ A wallpaper ═══════════════════════════════════════════════════════
        ClippingRectangle {
            id: pic
            anchors.fill: parent
            anchors.margins: card.ring
            visible: !st.isAction
            radius: Math.max(Tokens.radiusSm, card.corner - card.ring)
            color: card.palette.section

            // Until the picture is in: a cookie that turns on the card's own tone.
            Item {
                id: loading
                anchors.fill: parent
                visible: thumb.status !== Image.Ready
                MorphShape {
                    anchors.centerIn: parent
                    width: Tokens.iconXl
                    height: width
                    shape: "cookie9"
                    turns: false
                    fillColor: card.palette.alpha(card.panel.accent, 0.30)
                    NumberAnimation on rotation {
                        from: 0; to: 360
                        duration: Motion.spin * 6
                        loops: Animation.Infinite
                        running: loading.visible && Config.motionEnabled
                    }
                }
            }
            Image {
                id: thumb
                anchors.fill: parent
                opacity: status === Image.Ready ? 1 : 0
                scale: status === Image.Ready ? 1 : 1.06
                Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                Behavior on scale   { NumberAnimation { duration: Motion.spatialSlow; easing.type: Motion.travel } }
                source: card.panel.bust(st.thumb)
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                cache: true
                sourceSize.width: 360
                sourceSize.height: 240
            }
            // A GIF plays only under the pointer: a grid of them moving at once is a slot machine.
            AnimatedImage {
                anchors.fill: parent
                visible: st.isGif && hover.hovered
                source: visible ? card.panel.bust(st.thumb) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                playing: visible
            }

            StateLayer {
                id: feel
                anchors.fill: parent
                radius: pic.radius
                hovered: hover.hovered
                layerColor: card.panel.accent
            }

            // ── Top-left: what it is ──────────────────────────────────────────
            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Tokens.spacingSm
                spacing: Tokens.spacingXs

                // On screen: a cookie with a tick. Selecting: a tick box in its place.
                Item {
                    width: Tokens.iconLg + Tokens.spacingXs
                    height: width
                    visible: st.isCurrent || card.panel.selecting
                    MorphShape {
                        anchors.fill: parent
                        shape: st.isCurrent && !card.panel.selecting ? "cookie9" : "circle"
                        spec: Motion.springSpatialFast
                        fillColor: st.isCurrent || st.selected ? card.palette.primary : card.pill
                        strokeColor: st.isCurrent || st.selected ? "transparent" : card.palette.outline
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "check"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: card.palette.fgOnPrimary
                        opacity: st.isCurrent || st.selected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }
                // A scene (it moves).
                Rectangle {
                    width: Tokens.iconLg + Tokens.spacingXs
                    height: width
                    radius: width / 2
                    visible: st.isScene
                    color: card.pill
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "play_arrow"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: card.panel.accent
                    }
                }
                // The workspaces that wear it.
                Repeater {
                    model: card.owners.slice(0, 3).concat(card.owners.length > 3 ? [-(card.owners.length - 3)] : [])
                    delegate: Rectangle {
                        id: chip
                        required property int modelData
                        width: Math.max(Tokens.iconLg + Tokens.spacingXs, chipText.implicitWidth + Tokens.spacingMd)
                        height: Tokens.iconLg + Tokens.spacingXs
                        radius: height / 2
                        color: card.pill
                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData < 0 ? "+" + (-chip.modelData) : String(chip.modelData)
                            variant: "micro"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: card.panel.accent
                        }
                    }
                }
            }

            // ── Top-right: the tools ──────────────────────────────────────────
            // Under the pointer a capsule opens on a spring: the bookmark, a scene's options, the bin. A starred
            // one the pointer has left keeps just the mark, so what you kept reads from across the gallery.
            Rectangle {
                id: mark
                readonly property bool shown: st.isFav && !tools.shown && !card.armed && !card.panel.selecting
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.spacingSm
                width: Tokens.iconXl + Tokens.spacingXs
                height: width
                radius: width / 2
                color: card.pill
                opacity: mark.shown ? 1 : 0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "bookmark"
                    fill: 1
                    font.pixelSize: Tokens.iconLg
                    color: card.panel.accent
                }
            }
            Rectangle {
                id: tools
                readonly property bool shown: !card.panel.selecting && !card.armed && (hover.hovered || card.kbFocused)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.spacingSm
                width: toolRow.implicitWidth + Tokens.spacingXs * 2
                height: Tokens.iconXl + Tokens.spacingXs
                radius: height / 2
                color: card.pill
                opacity: Math.min(1, Math.max(0, toolsK.value))
                visible: tools.shown || toolsK.value > 0.005
                scale: 0.7 + 0.3 * Math.max(0, toolsK.value)
                transformOrigin: Item.TopRight
                SpringValue { id: toolsK; target: tools.shown ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }

                Row {
                    id: toolRow
                    anchors.centerIn: parent
                    spacing: 0
                    CardTool {
                        id: favTool
                        symbol: "bookmark"
                        filled: st.isFav
                        tint: st.isFav ? card.panel.accent : card.palette.fg
                        hoverTint: card.panel.accent
                        name: st.isFav ? Translation.tr("Remove the bookmark") : Translation.tr("Bookmark")
                        onActivated: { st.toggleFav(); favTool.bump() }
                    }
                    // A scene's own options.
                    CardTool {
                        visible: st.isScene
                        symbol: "equalizer"
                        hoverTint: card.panel.accent
                        name: Translation.tr("Scene options")
                        onActivated: card.panel.openProperties(st.key)
                    }
                    CardTool {
                        symbol: "close"
                        hoverTint: card.palette.danger
                        name: Translation.tr("Remove")
                        onActivated: st.doRemove()
                    }
                }
            }

            // ── Bottom: the name ──────────────────────────────────────────────
            Rectangle {
                id: nameTag
                readonly property bool shown: !card.armed && (hover.hovered || st.isCurrent || card.kbFocused)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.spacingSm
                width: Math.min(nameText.implicitWidth + Tokens.spacingMd * 2,
                                pic.width - Tokens.spacingSm * 2)
                height: Tokens.iconLg + Tokens.spacingSm
                radius: height / 2
                color: card.pill
                opacity: nameTag.shown ? 1 : 0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                StyledText {
                    id: nameText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingMd
                    width: parent.width - Tokens.spacingMd * 2
                    text: st.name
                    variant: "caption"
                    font.weight: st.isCurrent ? Font.DemiBold : Font.Medium
                    elide: Text.ElideMiddle
                }
            }
            // ── The middle: Apply ─────────────────────────────────────────────
            // A tick on a disc, and it tells what is happening to it:
            //   idle      the tick on a faint disc
            //   applying  the disc turns into a cookie that spins, the tick breathes
            //   applied   the disc fills, the tick comes in on it with a pop, "Applied", and the pill stays for a
            //             beat (the card then wears its own tick for good, and the pill has nothing left to say)
            Rectangle {
                id: apply
                property bool done: false
                readonly property bool shown: card.panel.selecting ? false
                    : card.panel.pickingActive ? (hover.hovered && st.isScene && !card.armed)
                    : (((hover.hovered || st.busy) && !st.applied && !card.armed) || apply.done)
                anchors.centerIn: parent
                width: applyRow.implicitWidth + Tokens.spacingLg * 2
                height: Tokens.iconXl + Tokens.spacingSm
                radius: height / 2
                color: card.panel.accent
                opacity: apply.shown ? 1 : 0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                SpringValue { id: applyPop; target: apply.shown ? 1 : 0; spec: Motion.springSpatialFast }
                scale: 0.72 + 0.28 * Math.max(0, applyPop.value)

                Timer { id: doneTimer; interval: 1100; onTriggered: apply.done = false }
                Connections {
                    target: st
                    function onBusyChanged() {
                        if (st.busy || card.panel.pickingActive) return
                        // Whether it landed is known a beat after the busy flag drops.
                        Qt.callLater(() => {
                            if (!st.applied) return
                            apply.done = true
                            doneTimer.restart()
                            tickPop.restart()
                        })
                    }
                }

                Row {
                    id: applyRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingSm

                    Item {
                        id: tick
                        anchors.verticalCenter: parent.verticalCenter
                        width: Tokens.iconLg + Tokens.spacingXs
                        height: width
                        property real pop: 1
                        property real breath: 1
                        SequentialAnimation {
                            id: tickPop
                            NumberAnimation { target: tick; property: "pop"; from: 0.4; to: 1.35; duration: Motion.respond; easing.type: Motion.travel }
                            NumberAnimation { target: tick; property: "pop"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
                        }
                        SequentialAnimation {
                            loops: Animation.Infinite
                            running: st.busy && apply.visible && Config.motionEnabled
                            NumberAnimation { target: tick; property: "breath"; to: 0.35; duration: Motion.standard; easing.type: Motion.inOut }
                            NumberAnimation { target: tick; property: "breath"; to: 1; duration: Motion.standard; easing.type: Motion.inOut }
                        }
                        MorphShape {
                            anchors.fill: parent
                            shape: st.busy ? "cookie6" : "circle"
                            spec: Motion.springSpatialFast
                            turns: false
                            fillColor: apply.done ? card.palette.fgOnPrimary
                                     : card.palette.alpha(card.palette.fgOnPrimary, st.busy ? 0.32 : 0.2)
                            Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                            NumberAnimation on rotation {
                                from: 0; to: 360
                                duration: Motion.spin
                                loops: Animation.Infinite
                                running: st.busy && apply.visible && Config.motionEnabled
                            }
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: card.panel.pickingActive ? "add" : "check"
                            fill: 1
                            font.pixelSize: Tokens.iconMd
                            color: apply.done ? card.panel.accent : card.palette.fgOnPrimary
                            opacity: st.busy ? tick.breath : 1
                            scale: tick.pop
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.panel.pickingActive ? Translation.tr("Assign")
                            : st.busy ? Translation.tr("Applying…")
                            : apply.done ? Translation.tr("Applied") : Translation.tr("Apply")
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: card.palette.fgOnPrimary
                    }
                }
            }
            // ══ Remove? ══════════════════════════════════════════════════════
            // Pressing the bin lays this over the picture: what will happen, and two plain buttons. The old way
            // (press the same spot again) asked you to read a label that had moved under your pointer. It also
            // swallows the card's own click, so nothing applies behind it; the pointer leaving the card calls it off.
            Item {
                id: confirm
                anchors.fill: parent
                opacity: card.armed ? 1 : 0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                Rectangle {
                    anchors.fill: parent
                    color: card.palette.alpha(card.palette.surface, 0.9)
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.spacingMd * 2
                    spacing: Tokens.spacingSm

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Tokens.iconXl + Tokens.spacingSm
                        height: width
                        MorphShape {
                            anchors.fill: parent
                            shape: card.armed ? "squircle" : "circle"
                            spec: Motion.springSpatialFast
                            fillColor: card.palette.danger
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "close"
                            fill: 1
                            font.pixelSize: Tokens.iconLg
                            color: card.palette.fgOnPrimary
                        }
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        font.weight: Font.DemiBold
                        text: st.isScene
                            ? (WallpaperEngine.stillSubscribed(st.key)
                                ? Translation.tr("Steam put it back: still subscribed. Remove it, then Unsubscribe on its page")
                                : Translation.tr("Delete it and unsubscribe?"))
                            : Translation.tr("Move it to the trash?")
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Tokens.spacingSm
                        Rectangle {
                            width: keepLabel.implicitWidth + Tokens.spacingLg * 2
                            height: Tokens.iconLg + Tokens.spacingSm
                            radius: height / 2
                            color: keepMouse.containsMouse ? card.palette.plate : card.palette.section
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            StyledText { id: keepLabel; anchors.centerIn: parent; text: Translation.tr("Keep"); variant: "label"; font.weight: Font.DemiBold }
                            MouseArea {
                                id: keepMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: st.removeLatch.disarm()
                                Accessible.role: Accessible.Button
                                Accessible.name: Translation.tr("Keep")
                                Accessible.onPressAction: st.removeLatch.disarm()
                            }
                        }
                        Rectangle {
                            width: removeLabel.implicitWidth + Tokens.spacingLg * 2
                            height: Tokens.iconLg + Tokens.spacingSm
                            radius: height / 2
                            color: card.palette.danger
                            opacity: removeMouse.containsMouse ? 1 : 0.88
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            StyledText { id: removeLabel; anchors.centerIn: parent; text: Translation.tr("Remove"); variant: "label"; font.weight: Font.DemiBold; color: card.palette.fgOnPrimary }
                            MouseArea {
                                id: removeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: st.doRemove()
                                Accessible.role: Accessible.Button
                                Accessible.name: Translation.tr("Remove")
                                Accessible.onPressAction: st.doRemove()
                            }
                        }
                    }
                }
            }
        }

        // The keyboard's place in the grid.
        Rectangle {
            anchors.fill: parent
            radius: card.corner
            color: "transparent"
            border.width: 2
            border.color: card.palette.focus
            opacity: card.kbFocused ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        HoverHandler {
            id: hover
            onHoveredChanged: if (!hovered) st.removeLatch.disarm()
        }
        // Under the pills (z: -1 puts it behind every button above), over the whole card: a left
        // click applies (or ticks, or assigns), a right click chooses the workspaces.
        MouseArea {
            id: press
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            enabled: card.panel.selecting || card.panel.pickingActive
                ? true
                : (st.isAction || (!card.panel.applyBusy && card.panel.blocked === ""))
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: function (m) { feel.press(m.x, m.y) }
            onReleased: feel.release()
            onCanceled: feel.release()
            onClicked: function (m) { if (m.button === Qt.RightButton) st.doChoose(); else st.doApply() }
        }
    }
}
