pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "widgets"

// ── WidgetLayer ───────────────────────────────────────────────────────────────
// Every desktop widget on one screen, in one full-screen surface behind the windows.
//
// ── Why one window for all of them ────────────────────────────────────────────
// The alternative — a layer-shell window per widget, positioned by its margins — was
// rejected on the drag path: moving a widget would be a surface reconfigure per frame,
// round-tripping through the compositor sixty times a second to slide a rectangle.
// Here a drag is a plain `x`/`y` change on an Item inside a surface that never moves.
//
// ── Which is why the input mask matters ───────────────────────────────────────
// A full-screen surface would swallow every click on the desktop. `mask` is composed
// from the widget items themselves — one Region per placed widget — so input lands on
// the tiles and passes through everywhere else. While arranging, the mask is dropped
// so the whole screen is grabbable.
//
// ── Keyboard ──────────────────────────────────────────────────────────────────
// `OnDemand` only when an editable widget (notes, reminders) is actually placed. That
// is the difference between "click the note to type in it" and a desktop that quietly
// competes for every keystroke: with no such widget the surface asks for no keyboard
// at all, which is what it should do for a clock.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    required property var modelData
    screen: root.modelData

    readonly property string screenName: root.modelData ? root.modelData.name : ""
    // For reading — counts, keyboard-focus, the empty state. NOT for use as a model:
    // see `placedIds` and the note on DesktopWidgets.idsFor.
    readonly property var placed: DesktopWidgets.forScreen(root.screenName)
    // The Repeater's and Instantiator's model. Ints, so an edit that changes no
    // membership compares equal and rebuilds nothing.
    readonly property var placedIds: DesktopWidgets.idsFor(root.screenName)
    readonly property bool arranging: UiState.widgetArrange

    // Any widget that takes text decides whether this surface wants the keyboard. The
    // ANSWER lives in the catalogue, not in a list of type names here — a new widget with
    // a text field would otherwise be silently unable to receive a keystroke, and nothing
    // about the symptom would point at this file.
    readonly property bool editable:
        root.placed.some(w => DesktopWidgets.takesText(w.type))

    // ── Surface ───────────────────────────────────────────────────────────────
    // Background normally — widgets belong behind your windows, like a wallpaper
    // element. While arranging they come to the Top, because you cannot drag a tile
    // you cannot see, and the whole point of arrange mode is looking at the desktop.
    WlrLayershell.layer: root.arranging ? WlrLayer.Top : WlrLayer.Background
    WlrLayershell.namespace: "quickshell-widgets"
    WlrLayershell.keyboardFocus:
        root.arranging ? WlrKeyboardFocus.OnDemand
      : root.editable  ? WlrKeyboardFocus.OnDemand
                       : WlrKeyboardFocus.None

    color: "transparent"
    exclusiveZone: 0

    anchors { top: true; bottom: true; left: true; right: true }

    // Mapped only when there is something to show. An empty desktop should not carry a
    // full-screen surface around, however transparent.
    visible: Config.widgetsEnabled && (root.placed.length > 0 || root.arranging)

    // ── Input mask ────────────────────────────────────────────────────────────
    // While arranging: no mask, the whole screen is live. Otherwise: exactly the widget
    // rectangles, so clicks land on tiles and pass through everywhere else.
    //
    // ── This was broken, and it is worth saying how ───────────────────────────
    // The first version built the list with `regionMaker.objectAt(i)` inside the
    // binding. That binding runs ONCE at creation — before the Instantiator has made
    // anything — and `objectAt` is a function call, not a reactive dependency, so it
    // never re-ran. The mask was permanently EMPTY, and an empty mask means the surface
    // accepts input NOWHERE: every widget was inert. Measured (0 of 3 regions resolved),
    // not guessed.
    //
    // Two changes fix it for good. The regions take their geometry from the MODEL
    // rather than from Repeater items, so nothing depends on which of the two lists
    // built first; and the list is rebuilt from the Instantiator's own add/remove
    // signals, which fire exactly when objects appear and disappear.
    mask: root.arranging ? null : passthrough

    Region { id: passthrough; regions: root._maskRegions }

    property var _maskRegions: []

    function _rebuildMask() {
        const out = []
        for (let i = 0; i < regionMaker.count; i++) {
            const r = regionMaker.objectAt(i)
            if (r) out.push(r)
        }
        root._maskRegions = out
    }

    Instantiator {
        id: regionMaker
        model: root.placedIds
        onObjectAdded:   root._rebuildMask()
        onObjectRemoved: root._rebuildMask()

        delegate: Region {
            id: region
            required property int modelData
            // Resolved from the id rather than carried in the model, so moving or
            // resizing a widget updates this region's geometry through a BINDING
            // instead of by rebuilding every region on the screen.
            readonly property var rec: DesktopWidgets.get(region.modelData)
            x:      region.rec ? region.rec.x : 0
            y:      region.rec ? region.rec.y : 0
            width:  region.rec ? DesktopWidgets.widthOf(region.rec.size)  : 0
            height: region.rec ? DesktopWidgets.heightOf(region.rec.size) : 0
            radius: Tokens.radiusWidget
        }
    }

    // ── The wallpaper, as a texture ───────────────────────────────────────────
    // ONE copy per screen, shared by every tile's glass shader. It must be a valid
    // TEXTURE PROVIDER while being invisible, and getting that combination right took
    // two wrong answers, both of which fail the same way and in silence:
    //
    //   • `visible: false` — an invisible item is never rendered, so its texture stays
    //     0x0. A ShaderEffect with an unbound sampler then draws NOTHING AT ALL, not
    //     even a hardcoded flat colour.
    //   • `opacity: 0` — exactly the same outcome, because Qt culls fully transparent
    //     items before they ever reach the renderer. This one shipped, and the running
    //     shell reported it once per tile:
    //         ShaderEffect: Texture t1 is not assigned a valid texture provider
    //     The comment here previously ASSERTED that opacity 0 left a live provider. It
    //     did not. The log is what settled it.
    //
    // `layer.enabled` is the fix: the item is rendered into its own offscreen surface,
    // which is what `textureProvider()` then hands to the shader. That render happens
    // regardless of how the layer is later composited into the scene, so the picture is
    // available to sample while being invisible on screen.
    //
    // The opacity is a hair above zero rather than at it, so no cull can short-circuit
    // the layer before it renders. At 0.004 over a wallpaper that is already showing the
    // same picture, it is not a thing anyone can see.
    //
    // `sourceSize` caps the decode at the screen's own size. Without it a 4K picture on a
    // 1080p screen decodes at 4K and costs four times the memory to sample from.
    Image {
        id: wallpaperTexture
        anchors.fill: parent
        opacity: 0.004
        z: -100
        source: Wallpaper.currentPath === "" ? "" : "file://" + Wallpaper.currentPath
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: true
        cache: true
        layer.enabled: true
        layer.smooth: true
        // Only worth holding while something will actually sample it.
        visible: Config.widgetGlass
    }

    // Null until the picture is actually decoded AND the layer has something in it, so a
    // tile falls back to the layered material rather than binding a sampler that is not
    // ready. `Image.Ready` alone was not enough: it says the file decoded, not that the
    // item has been rendered into a texture.
    readonly property Item backdropTexture:
        (Config.widgetGlass
         && wallpaperTexture.status === Image.Ready
         && wallpaperTexture.width > 0 && wallpaperTexture.height > 0)
            ? wallpaperTexture : null

    // ── Arrange-mode backdrop ─────────────────────────────────────────────────
    // Dims the desktop and draws the snap grid, so you can see where things will land.
    Rectangle {
        anchors.fill: parent
        color: Colors.alpha(Colors.base, 0.45)
        opacity: root.arranging ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        // Dots, not lines: a full grid of lines over a wallpaper is visual noise, and
        // the dots mark exactly the points a tile's corner can land on.
        Canvas {
            id: gridCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Colors.alpha(Colors.fg, 0.22)
                const g = Config.widgetGrid
                for (let x = 0; x < width; x += g)
                    for (let y = 0; y < height; y += g)
                        ctx.fillRect(x, y, 1, 1)
            }
            // Repainting a screen-sized dot field on every frame would be absurd; it is
            // static, so it repaints only when the grid or the size actually changes.
            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: Config
                function onWidgetGridChanged() { gridCanvas.requestPaint() }
            }
        }
    }

    // ── The widgets ───────────────────────────────────────────────────────────
    Repeater {
        id: repeater
        // IDs, never records — see DesktopWidgets.idsFor. A record model made every edit
        // rebuild every tile; it also fed a record object into the delegate's `int
        // modelData`, which coerced to garbage, so `get()` returned null and every tile
        // built empty. The mask Instantiator already uses placedIds; this must match.
        model: root.placedIds

        delegate: WidgetFrame {
            id: frame
            // The ID, not the record. See DesktopWidgets.idsFor: a model of records made
            // every edit rebuild every tile on the screen.
            required property int modelData
            required property int index

            // The record, resolved reactively. A widget removed while this delegate is
            // being torn down resolves to null for an instant, so everything downstream
            // tolerates that rather than assuming a record is always there.
            readonly property var rec: DesktopWidgets.get(frame.modelData)

            model:     frame.rec ?? ({ id: frame.modelData, type: "", screen: "",
                                       x: 0, y: 0, size: "small", opts: {} })
            backdrop:  root.backdropTexture
            arranging: root.arranging
            boundsW:   root.width
            boundsH:   root.height

            // Widgets only run their timers when they can be seen. `root.visible` is
            // false whenever the feature is off or the screen is empty, and a clock
            // ticking behind a disabled layer is exactly the waste this avoids.
            readonly property bool live: root.visible

            onCommitted: function (nx, ny) {
                DesktopWidgets.move(frame.modelData, nx, ny, root.width, root.height)
            }

            // ── Tapping the tile ──────────────────────────────────────────────
            // The frame owns the gesture and knows nothing about what it means; a widget
            // that has a whole-tile action declares `function tileTap()` and gets called.
            // Optional by design — most of these are displays, and a tile that responds
            // to a tap by doing nothing is worse than one that plainly does not respond.
            onTapped: {
                const w = widgetLoader.item
                if (w && typeof w.tileTap === "function") w.tileTap()
            }

            Loader {
                id: widgetLoader
                anchors.fill: parent
                asynchronous: true

                // ── setSource, NOT the `source` property ──────────────────
                // The widget types declare `opts`, `size` and `widgetId` as REQUIRED.
                // Assigning `source` constructs the object with none of them set —
                // Qt warns once per property, and worse, the widget's own
                // Component.onCompleted runs against uninitialised values. NotesWidget
                // reads `opts.text` there, so a saved note came back blank every time
                // the desktop loaded. `setSource` takes initial properties, which is
                // the only way to satisfy a required property through a Loader.
                function build() {
                    // A null record here means the widget was removed, or the store has
                    // not resolved it yet. Returning is right, but it MUST be retried:
                    // nothing else calls build(), so an early return that never runs
                    // again leaves a permanently empty tile — a frame with no widget in
                    // it, which is indistinguishable from "the widgets don't load".
                    if (!frame.rec) return
                    const t = frame.rec.type
                    const file = "widgets/" + t.charAt(0).toUpperCase() + t.slice(1) + "Widget.qml"
                    widgetLoader.setSource(file, {
                        opts:     frame.rec.opts,
                        size:     frame.rec.size,
                        widgetId: frame.rec.id
                    })
                }

                Component.onCompleted: widgetLoader.build()

                onLoaded: {
                    widgetLoader.item.active = Qt.binding(() => frame.live)
                    widgetLoader.item.accent = Qt.binding(() => frame.accent)
                }

                // The record is replaced on every store change, so the loaded widget
                // has to be re-fed rather than bound: `modelData` is a plain JS object
                // and a binding onto its fields would not re-evaluate on replacement.
                // A TYPE change needs a rebuild; anything else is just new values.
                // Watches the RECORD, not `modelData` — modelData is now a constant id
                // for this delegate's whole life, so a handler on it would never fire.
                Connections {
                    target: frame
                    function onRecChanged() {
                        if (!frame.rec) return
                        // The retry for the case above. Also covers a TYPE change, which
                        // is a different file and cannot be re-fed.
                        if (!widgetLoader.item) {
                            widgetLoader.build()
                            return
                        }
                        widgetLoader.item.opts = frame.rec.opts
                        widgetLoader.item.size = frame.rec.size
                    }
                }
            }
        }
    }

    // ── Done ──────────────────────────────────────────────────────────────────
    // Arrange mode needs a way out that does not depend on remembering a key. Escape
    // works too, and is handled here because this surface holds the keyboard while
    // arranging.
    PanelButton {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingXxl * 2
        visible: root.arranging
        variant: "primary"
        glyph: "󰄬"
        label: "Done arranging"
        onActivated: UiState.widgetArrange = false
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.spacingXxl * 2
        visible: root.arranging && root.placed.length === 0
        text: "No widgets on this screen yet — add some from Settings → Widgets."
        variant: "body"
        emphasis: "muted"
    }

    Item {
        anchors.fill: parent
        focus: root.arranging
        Keys.onEscapePressed: UiState.widgetArrange = false
    }
}
