pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../services"

// ── WidgetPreview ─────────────────────────────────────────────────────────────
// A real widget, rendered small. Not a mock-up, not an icon — the same WidgetFrame and
// the same widget file the desktop uses, inside a scale transform.
//
// ── Why the real thing rather than a picture ──────────────────────────────────
// A drawn approximation is a second implementation of every widget's layout, and it
// starts lying the first time one of them changes. Scaling the real component means the
// preview cannot disagree with the desktop, and it picks up the accent, the corner
// radius and the translucency settings for free — which is the point, since those are
// exactly what the settings page is for changing.
//
// ── Previews are INERT ────────────────────────────────────────────────────────
// `active: false` on the loaded widget, so no preview starts a clock ticking, and
// WeatherWidget skips its refcount acquire — a settings page should not be issuing
// network requests just by being open. The widgets still render their current values,
// because each one seeds itself from the clock or the service on construction.
Item {
    id: root

    required property string type
    property string size: ""
    property var    opts: ({})
    property color  accent: Colors.of(QsWindow.window).primary

    // The box to fit inside. The preview scales DOWN to fit and never up — an upscaled
    // widget looks like a mistake, and at natural size it is already legible.
    property real boxWidth:  280
    property real maxHeight: 180

    // The widget instance inside, exposed so a test can reach it. Nothing in the shell
    // reads this — a preview is for looking at — but without it the only way to check
    // that a type's tap action exists and is safe to call is to click it by hand.
    readonly property alias widget: previewLoader.item

    readonly property var meta: DesktopWidgets.info(root.type)
    readonly property string useSize:
        root.size !== "" ? root.size
                         : (root.meta && root.meta.sizes.length > 0 ? root.meta.sizes[0] : "small")

    readonly property real natW: DesktopWidgets.widthOf(root.useSize)
    readonly property real natH: DesktopWidgets.heightOf(root.useSize)
    readonly property real factor:
        Math.min(1, root.boxWidth / root.natW, root.maxHeight / root.natH)

    implicitWidth:  root.natW * root.factor
    implicitHeight: root.natH * root.factor

    Item {
        width:  root.natW
        height: root.natH
        transform: Scale { xScale: root.factor; yScale: root.factor }

        WidgetFrame {
            id: frame
            anchors.fill: parent
            // A synthetic record. The frame only reads size/opts/type for display, and
            // `arranging` stays false, so nothing here can reach the store — a preview
            // must not be able to move or delete the real widget it depicts.
            model: ({
                id: -1,
                type: root.type,
                screen: "",
                x: 0, y: 0,
                size: root.useSize,
                opts: root.opts
            })

            Loader {
                id: previewLoader
                anchors.fill: parent
                anchors.margins: Tokens.spacingXl

                // Same setSource contract as the layer: these widgets declare required
                // properties, and a plain `source` would construct them with none set.
                function build() {
                    const t = root.type
                    previewLoader.setSource(
                        "" + t.charAt(0).toUpperCase() + t.slice(1) + "Widget.qml",
                        // `active: false` is an INITIAL property, not something set in
                        // onLoaded. A widget acquires its service in its own
                        // Component.onCompleted, which runs BEFORE the Loader reports
                        // the item — so assigning it afterwards meant every preview
                        // took a refcount and dropped it a moment later. For the
                        // weather tile that is a real HTTP request per preview built,
                        // which is exactly what "previews are inert" promises not to do.
                        { opts: root.opts, size: root.useSize, widgetId: -1,
                          active: false })
                }
                Component.onCompleted: previewLoader.build()

                onLoaded: previewLoader.item.accent = Qt.binding(() => root.accent)

                Connections {
                    target: root
                    function onOptsChanged() {
                        if (previewLoader.item) previewLoader.item.opts = root.opts
                    }
                    function onUseSizeChanged() {
                        if (previewLoader.item) previewLoader.item.size = root.useSize
                    }
                    // A different TYPE is a different file, so it has to be rebuilt
                    // rather than re-fed.
                    function onTypeChanged() { previewLoader.build() }
                }
            }
        }
    }

    // Previews are for looking at. Anything clickable belongs to the row around them,
    // which is why this swallows nothing and the widget inside is disabled.
    Component.onCompleted: if (previewLoader.item) previewLoader.item.enabled = false
}
