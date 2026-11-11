pragma Singleton
import QtQuick

// ── WallFrame ─────────────────────────────────────────────────────────────────
// Which WallpaperView draws which screen, so another surface can read how the wallpaper
// is framed there (zoom, parallax pan, the picture on the plane). The desktop tiles' glass
// is the reader: it refracts the wallpaper, and the wallpaper moves.
//
// Holds the view itself, not copies of its numbers: a copy would be a second writer, and
// a pan that changes every frame under the pointer would then be copied every frame.
// `views` is replaced, never mutated in place, so a binding on `of()` re-evaluates when a
// screen's view appears or goes.
QtObject {
    id: root

    property var views: ({})

    function of(name) { return root.views[name] ?? null }

    function register(name, view) {
        if (name === "") return
        const v = Object.assign({}, root.views)
        v[name] = view
        root.views = v
    }

    // Only the view that is registered may remove itself: a reload can build the new view
    // before the old one is destroyed.
    function unregister(name, view) {
        if (root.views[name] !== view) return
        const v = Object.assign({}, root.views)
        delete v[name]
        root.views = v
    }
}
