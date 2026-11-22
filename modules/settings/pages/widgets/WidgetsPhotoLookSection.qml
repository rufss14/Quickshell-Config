pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../desktop/widgets"
import "../.."

// ── WidgetsPhotoLookSection ── how the photo frame looks: its outline, its background, the picture's tone.
// The backdrop chip ("Backdrop blur") and the picture fader ("Picture blur") say which blur they are. Part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to.
Section {
    id: look
    required property var page

    readonly property var sel: page.selected

    grouped:  true
    visible:  !!look.sel && look.sel.type === "photo"
    symbol:   "palette"
    title:    Translation.tr("Photo look")
    subtitle: look.sel ? Translation.tr("%1 background").arg(look.bgLabel) : ""

    readonly property string bgMode: look.sel ? (look.sel.opts.bgMode ?? "solid") : "solid"
    readonly property string bgLabel: look.bgMode === "transparent" ? Translation.tr("Transparent")
                                    : look.bgMode === "glass"       ? Translation.tr("Glass")
                                    : look.bgMode === "blur"        ? Translation.tr("Blurred")
                                    :                                 Translation.tr("Solid")

    // The frame's outline: the tile's own rounded rectangle, or a shape.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        StyledText { text: Translation.tr("Frame"); variant: "caption"; emphasis: "dim" }
        ChipRow {
            Layout.fillHeight: false
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "rect",     label: Translation.tr("Rounded")  },
                { value: "cookie9",  label: Translation.tr("Cookie")   },
                { value: "clover",   label: Translation.tr("Clover")   },
                { value: "sunny",    label: Translation.tr("Sunny")    },
                { value: "squircle", label: Translation.tr("Squircle") },
                { value: "circle",   label: Translation.tr("Circle")   },
                { value: "burst",    label: Translation.tr("Burst")    }
            ]
            current: look.sel ? (look.sel.opts.shape ?? "rect") : "rect"
            onPicked: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "shape", v) }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        StyledText { text: Translation.tr("Appearance"); variant: "caption"; emphasis: "dim" }
        TabStrip {
            Layout.fillWidth: true
            connected: true
            model: [
                { value: "solid",       label: Translation.tr("Solid")         },
                { value: "transparent", label: Translation.tr("Transparent")   },
                { value: "glass",       label: Translation.tr("Glass")         },
                { value: "blur",        label: Translation.tr("Backdrop blur") }
            ]
            current: look.bgMode
            onPicked: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "bgMode", v) }
        }
    }

    Fader {
        label: Translation.tr("Background opacity")
        accent: Colors.of(QsWindow.window).primary
        from: 0; to: 1; step: 0.05
        value: look.sel ? (look.sel.opts.bgOpacity ?? 1.0) : 1.0
        readout: Math.round((look.sel ? (look.sel.opts.bgOpacity ?? 1.0) : 1.0) * 100) + "%"
        onCommit: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "bgOpacity", v) }
    }

    SettingRow {
        rowTap: true
        label: Translation.tr("Shape rotation")
        onTapped: DesktopWidgets.setOpt(look.page.selectedId, "shapeRot", !(!!look.sel && look.sel.opts.shapeRot === true))
        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: !!look.sel && look.sel.opts.shapeRot === true
            onToggled: DesktopWidgets.setOpt(look.page.selectedId, "shapeRot", !(!!look.sel && look.sel.opts.shapeRot === true))
        }
    }

    Fader {
        label: Translation.tr("Brightness")
        accent: Colors.of(QsWindow.window).primary
        from: 0.5; to: 1.5; step: 0.05
        value: look.sel ? (look.sel.opts.brightness ?? 1.0) : 1.0
        onCommit: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "brightness", v) }
    }
    Fader {
        label: Translation.tr("Saturation")
        accent: Colors.of(QsWindow.window).primary
        from: 0; to: 2; step: 0.05
        value: look.sel ? (look.sel.opts.saturation ?? 1.0) : 1.0
        onCommit: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "saturation", v) }
    }
    Fader {
        label: Translation.tr("Picture blur")
        accent: Colors.of(QsWindow.window).primary
        from: 0; to: 1; step: 0.05
        value: look.sel ? (look.sel.opts.imgBlur ?? 0) : 0
        onCommit: function (v) { DesktopWidgets.setOpt(look.page.selectedId, "imgBlur", v) }
    }
}
