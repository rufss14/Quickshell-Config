pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../desktop/widgets"
import "../.."

// ── WidgetsPhotoSection ── the photo frame's pictures: what it shows, how often it changes, how it moves.
// Its looks (frame shape, background, image tone) are the next group, WidgetsPhotoLookSection.
// Part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to.
Section {
    id: photo
    required property var page

    readonly property var    sel: page.selected
    // What this frame shows. Each frame has its own (several can be placed).
    readonly property string src: photo.sel ? (photo.sel.opts.source ?? "library") : "library"
    readonly property string stored: !photo.sel ? ""
        : photo.src === "folder" ? (photo.sel.opts.folder ?? "")
        : (photo.sel.opts.image ?? "")

    function isOn(key, defOn) {
        return !!photo.sel && (defOn ? photo.sel.opts[key] !== false : photo.sel.opts[key] === true)
    }
    function flip(key, defOn) {
        DesktopWidgets.setOpt(photo.page.selectedId, key, !photo.isOn(key, defOn))
    }

    grouped:  true
    visible:  !!photo.sel && photo.sel.type === "photo"
    symbol:   "image"
    title:    Translation.tr("Photo frame")
    subtitle: photo.src === "library" ? Translation.tr("Your wallpapers")
            : photo.src === "folder"  ? Translation.tr("A folder")
            :                           Translation.tr("One picture")

    SettingRow {
        label: Translation.tr("Shows")

        TabStrip {
            connected: true
            implicitWidth: Tokens.fieldHeight * 12
            model: [
                { value: "library", label: Translation.tr("Wallpapers")  },
                { value: "folder",  label: Translation.tr("A folder")    },
                { value: "image",   label: Translation.tr("One picture") }
            ]
            current: photo.src
            onPicked: function (v) { DesktopWidgets.setOpt(photo.page.selectedId, "source", v) }
        }
    }

    // The folder or picture, and the button that opens the browser.
    SettingRow {
        visible: photo.src !== "library"
        label:   photo.src === "folder" ? Translation.tr("Folder") : Translation.tr("Picture")
        detail:  photo.stored !== "" ? photo.stored
               : photo.src === "folder" ? Translation.tr("No folder yet") : Translation.tr("No picture yet")

        PanelButton {
            capsule: true
            variant: "ghost"
            symbol: photo.src === "folder" ? "folder" : "image"
            label: Translation.tr("Choose…")
            onActivated: {
                const p = photo.page.photoPicker
                p.folders = photo.src === "folder"
                p.title = p.folders ? Translation.tr("Choose a folder") : Translation.tr("Choose a picture")
                p.current = DesktopWidgets.expandPath(photo.stored)
                p.show(DesktopWidgets.expandPath(photo.stored))
            }
        }
    }

    Fader {
        label: Translation.tr("Change every")
        accent: Colors.of(QsWindow.window).primary
        from: 10; to: 300; step: 5
        value: photo.sel ? (photo.sel.opts.seconds ?? 30) : 30
        readout: (photo.sel ? (photo.sel.opts.seconds ?? 30) : 30) + "s"
        onCommit: function (v) { DesktopWidgets.setOpt(photo.page.selectedId, "seconds", Math.round(v)) }
    }

    SettingRow {
        rowTap: true
        label: Translation.tr("Slow zoom")
        onTapped: photo.flip("pan", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: photo.isOn("pan", true); onToggled: photo.flip("pan", true) }
    }
    SettingRow {
        rowTap: true
        label: Translation.tr("Shuffle")
        onTapped: photo.flip("shuffle", false)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: photo.isOn("shuffle", false); onToggled: photo.flip("shuffle", false) }
    }

    Fader {
        label: Translation.tr("Pan strength")
        accent: Colors.of(QsWindow.window).primary
        from: 0.2; to: 1.5; step: 0.1
        value: photo.sel ? (photo.sel.opts.panStr ?? 1.0) : 1.0
        onCommit: function (v) { DesktopWidgets.setOpt(photo.page.selectedId, "panStr", v) }
    }
    Fader {
        label: Translation.tr("Fade speed")
        accent: Colors.of(QsWindow.window).primary
        from: 100; to: 1000; step: 50
        value: photo.sel ? (photo.sel.opts.fadeMs ?? 300) : 300
        readout: (photo.sel ? (photo.sel.opts.fadeMs ?? 300) : 300) + "ms"
        onCommit: function (v) { DesktopWidgets.setOpt(photo.page.selectedId, "fadeMs", Math.round(v)) }
    }
}
