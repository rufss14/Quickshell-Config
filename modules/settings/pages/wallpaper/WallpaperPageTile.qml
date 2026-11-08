pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperPageTile — WallpaperPage.qml's inline `WallTile`, moved into its own file (2026-11-08).
// ── WallTile ─────────────────────────────────────────────────────────────
// One gallery tile: picture (animated for GIF previews, but only on the
// visible page), name bar, current mark, hover Apply, and the ✕ delete.
//
// Branch on the ENTRY's shape, never on root.isImages: during a tab switch
// the flag flips while the outgoing tiles still exist for a frame, so a
// string entry got asked for `.id` — the entry itself can't be out of sync.
Item {
    id: tile
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page

    property var entry
    property int pageIndex: 0
    // A gallery entry is one of THREE shapes: a string (an image's path), a scene
    // object, or the action card ({ action, glyph, title, caption }).
    readonly property bool isObj:
        tile.entry !== undefined && typeof tile.entry === "object"
            && tile.entry !== null
    readonly property bool isAction: tile.isObj && tile.entry.action !== undefined
    readonly property bool isScene:  tile.isObj && !tile.isAction

    // Lifts a couple of pixels under the pointer, on the spring.
    transform: Translate {
        y: hover.hovered && !tileMouse.pressed ? -2 : 0
        Behavior on y {
            NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline
                              easing.bezierCurve: Motion.spring }
        }
    }

    readonly property string key: tile.isObj
        ? (tile.entry.id ?? "")
        : String(tile.entry ?? "")
    readonly property string name: tile.isObj
        ? (tile.entry.title ?? "")
        : String(tile.entry ?? "").split("/").pop()
    readonly property string thumb: {
        if (tile.isAction) return ""
        if (!tile.isScene) {
            const p = String(tile.entry ?? "")
            return p !== "" ? page.bust("file://" + p) : ""
        }
        const prev = tile.entry.preview ?? ""
        return prev !== "" ? page.bust("file://" + prev) : ""
    }
    readonly property bool isGif: tile.thumb.toLowerCase().indexOf(".gif") !== -1
    readonly property bool animate: page.galleryPager.currentIndex === tile.pageIndex
    readonly property bool isCurrent: page.isImages
        ? (!page.sceneOnScreen && !Config.wallMaterial && Wallpaper.current === tile.name)
        : (page.sceneOnScreen && WallpaperEngine.current === tile.key)
    // See WallpaperPanel's tile: `applied` = current AND on every workspace.
    readonly property string value: page.isImages ? tile.key : "scene:" + tile.key
    readonly property bool applied: tile.isCurrent && Wallpaper.everywhere(tile.value, true)
    readonly property bool busy: page.isImages
        ? (Wallpaper.applying && Wallpaper.applyingPath === tile.key)
        : (WallpaperEngine.busy && Config.wpeCurrent === tile.key)

    readonly property bool isFav: tile.isScene
        ? Config.wpeFavorites.indexOf(tile.key) !== -1
        : Config.wallFavorites.indexOf(tile.name) !== -1

    function toggleFav() {
        if (tile.isScene) Config.wpeFavToggle(tile.key)
        else              Config.wallFavToggle(tile.name)
    }
    function doApply() {
        if (tile.isAction) { page.runAction(tile.entry.action); return }
        // A workspace is waiting for a wallpaper: this one becomes its own.
        if (page.pickingWs > 0) {
            Wallpaper.assign(tile.value, [page.pickingWs])
            page.pickingWs = 0
            return
        }
        if (page.pickingActive) {
            if (!tile.isScene) return
            if (page.pickingScreens.length > 0)
                WallpaperEngine.spanMonitors(page.pickingScreens, tile.key)
            else
                WallpaperEngine.assignMonitor(page.pickingForScreen, tile.key)
            page.pickingForScreen = ""
            page.pickingScreens = []
            return
        }
        if (page.applyBusy || page.blocked !== "" || tile.applied) return
        if (page.isImages) Wallpaper.pick(tile.key)
        else               Wallpaper.pickScene(tile.key)
    }
    function doChoose() {
        if (tile.isAction || page.anyPicking || page.applyBusy || page.blocked !== "") return
        Wallpaper.choose(tile.value)
    }
    function doDelete() { deleteLatch.trigger() }

    // ── Removing: armed, then confirmed ─────────────────────────────────
    // An image goes to the TRASH (gio trash). A scene's files are deleted AND
    // its Workshop page opens — unsubscribing is a Steam account action, and
    // delete alone means Steam re-downloads it on the next sync.
    ArmLatch {
        id: deleteLatch
        onConfirmed: {
            if (page.isImages) {
                Wallpaper.remove(tile.key)
            } else {
                WallpaperEngine.removeAndUnsubscribe(tile.key)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: tile.isAction && hover.hovered
            ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10)
            : Colors.of(QsWindow.window).surfaceContainer
        Behavior on color { ColorAnimation { duration: Motion.respond } }
        border.width: tile.isAction ? Tokens.borderWidth : tile.isCurrent ? 2 : (hover.hovered ? 1 : 0)
        border.color: deleteLatch.armed ? Colors.of(QsWindow.window).danger
                    : tile.isCurrent ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).outlineFocus
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: Tokens.borderWidth
            radius: Tokens.radiusSm - Tokens.borderWidth
            color: "transparent"

            // ── The action card ─────────────────────────────────────────
            // The same anatomy as a picture — an inset where the picture would be,
            // the name on the bar under it — so it reads as the first item of the
            // gallery rather than a different kind of object.
            ColumnLayout {
                visible: tile.isAction
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Tokens.spacingMd
                width: parent.width - Tokens.spacingLg * 2
                spacing: Tokens.spacingXs

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    glyph: tile.isAction ? tile.entry.glyph : ""
                    color: Colors.of(QsWindow.window).primary
                    variant: "title"
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.isAction ? tile.entry.caption : ""
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Image {
                anchors.fill: parent
                source: tile.isGif ? "" : tile.thumb
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 480
                smooth: true
            }
            AnimatedImage {
                anchors.fill: parent
                source: tile.isGif ? tile.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                playing: tile.isGif && tile.animate
                paused: !tile.animate
            }
            MaterialIcon {
                anchors.centerIn: parent
                glyph: "󰋩"
                variant: "title"
                emphasis: "dim"
                visible: tile.thumb === "" && !tile.isAction
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 26
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: "check"
                        fill: 1
                        color: Colors.of(QsWindow.window).primary
                        variant: "caption"
                        visible: tile.isCurrent
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: tile.name
                        variant: "caption"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: tile.isAction ? ""
                            : !tile.isScene
                            ? String(tile.entry ?? "").split(".").pop().toLowerCase()
                            : (tile.entry.type ?? "")
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
            }

            // ── Hover: the one primary action ─────────────────────────
            Rectangle {
                anchors.fill: parent
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.55)
                opacity: (hover.hovered || deleteLatch.armed) && !tile.isAction ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                PanelButton {
                    capsule: true
                    anchors.centerIn: parent
                    label: page.anyPicking ? "Assign"
                         : tile.busy ? "Applying…"
                         : tile.applied ? "Applied" : "Apply"
                    symbol: "check"
                    variant: (page.anyPicking || !tile.applied) ? "primary" : "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    // Picking only cares whether this tile IS a scene — a scene
                    // that's already the default (tile.isCurrent) can still be
                    // assigned to a monitor, and pywal being missing (`blocked`)
                    // has nothing to do with a Config-only assignment.
                    enabled: page.pickingWs > 0 ? true
                            : page.pickingActive ? tile.isScene
                            : (!page.applyBusy && page.blocked === "" && !tile.applied)
                    onActivated: tile.doApply()
                }
                StyledText {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Tokens.spacingLg * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    visible: deleteLatch.armed
                    text: page.isImages
                        ? "Press ✕ again to move it to the trash."
                        : WallpaperEngine.stillSubscribed(tile.key)
                          ? "Steam put it back: it is still subscribed. Press ✕ again, "
                            + "then click Unsubscribe on its Workshop page."
                          : "Press ✕ again to delete the files and open its Workshop "
                            + "page — unsubscribe there, or Steam downloads it again."
                }
            }

            // ── Delete: the ✕, top-left ─────────────────────────────
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Tokens.spacingSm
                width: Tokens.iconMd + 4
                height: Tokens.iconMd + 4
                radius: width / 2
                color: deleteLatch.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                border.width: Tokens.borderWidth
                border.color: deleteLatch.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).outline
                opacity: (hover.hovered || deleteLatch.armed) && !tile.isAction ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                Behavior on color   { ColorAnimation  { duration: Motion.respond } }

                MaterialIcon {
                    anchors.centerIn: parent
                    name: "close"
                    variant: "caption"
                    color: deleteLatch.armed ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.doDelete()
                }
            }

            // ── Favourite: the star, top-right ─────────────────────
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.spacingSm
                width: Tokens.iconMd + 4
                height: Tokens.iconMd + 4
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                border.width: Tokens.borderWidth
                border.color: tile.isFav ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).outline
                opacity: (hover.hovered || tile.isFav) && !tile.isAction ? 1.0 : 0.0
                visible: opacity > 0.005
                Behavior on opacity      { NumberAnimation { duration: Motion.respond } }
                Behavior on border.color { ColorAnimation  { duration: Motion.respond } }

                StyledText {
                    anchors.centerIn: parent
                    text: ""   // Font Awesome solid star
                    font.family: Tokens.fontGlyphs
                    variant: "caption"
                    color: tile.isFav ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.toggleFav()
                }
            }

            // ── Customise: the tune glyph, bottom-left ──────────────
            // Scenes only — a plain image has no author-defined properties
            // to expose. Opens the Properties view for this scene.
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: Tokens.spacingSm
                width: Tokens.iconMd + 4
                height: Tokens.iconMd + 4
                radius: width / 2
                visible: tile.isScene
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).outline
                opacity: hover.hovered ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                MaterialIcon {
                    anchors.centerIn: parent
                    name: "equalizer"
                    variant: "caption"
                    color: Colors.of(QsWindow.window).fg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.openProperties(tile.key)
                }
            }

            BusyDot {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: Tokens.spacingSm
                running: tile.busy
                tint: Colors.of(QsWindow.window).primary
            }
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered) deleteLatch.disarm()
    }
    MouseArea {
        id: tileMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // Picking is a Config-only write (assignMonitor/spanMonitors) — it
        // doesn't touch the theming pipeline or the renderer's own busy state,
        // so it isn't gated by applyBusy/blocked the way a real apply is.
        enabled: tile.isAction ? !page.anyPicking
               : page.anyPicking ? true : (!page.applyBusy && page.blocked === "")
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) { if (m.button === Qt.RightButton) tile.doChoose(); else tile.doApply() }
        z: -1
    }
}
