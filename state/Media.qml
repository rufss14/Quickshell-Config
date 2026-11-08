pragma Singleton

import QtQuick

// ── Media ─────────────────────────────────────────────────────────────────────
// Whether qt6-multimedia is installed — i.e. whether the clip editor can play.
// Morph's probe, for the same reason: a missing QML module makes the importing file
// fail to exist, so nothing imports QtMultimedia but components/media/ClipPlayer,
// and that file is only ever created through here and a Loader by URL.
//
// `checked` false = not known yet; `available` false after that = the editor shows
// its poster and says to install qt6-multimedia qt6-multimedia-ffmpeg.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property bool available: false
    property bool checked: false
    readonly property url playerUrl: Qt.resolvedUrl("../components/media/ClipPlayer.qml")

    Component.onCompleted: root._resolve(Qt.createComponent(root.playerUrl, Component.Asynchronous))

    function _resolve(comp) {
        if (comp.status === Component.Ready) {
            root.available = true
            root.checked = true
            comp.destroy()
        } else if (comp.status === Component.Error) {
            root.available = false
            root.checked = true
        } else {
            comp.statusChanged.connect(function () { root._resolve(comp) })
        }
    }
}
