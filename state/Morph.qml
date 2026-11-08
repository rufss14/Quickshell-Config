pragma Singleton
import QtQuick

// ── Morph ─────────────────────────────────────────────────────────────────────
// "Is the blob plugin actually here." One flag, nothing else — this is the ONLY
// safe way to know, because `import Quicktest.Blobs` cannot appear anywhere this
// file (or any eagerly-loaded file like Bar.qml) can see at compile time.
//
// ── Why a probe, and why it can't just be a property default ─────────────────
// A missing QML module is "an unresolved type from a missing import" — CLAUDE.md's
// own list of hard, silent failures: the file that imports it doesn't fail to
// RUN, it fails to EXIST, and that cascades (PrivacyPill's redeclared property is
// the same class of bug, different cause). `Bar.qml` is instantiated directly by
// shell.qml's Variants, so if it — or anything it directly imports — carried
// `import Quicktest.Blobs`, a machine that hasn't run
// scripts/build-blobs-plugin.sh would lose the entire bar, not just the morph.
//
// `Qt.createComponent()` is the one place QML lets you ATTEMPT an import and get
// a catchable status back instead of a load-time failure — it's what `Loader`
// itself uses internally. MorphProbe.qml is the only file in this repo that
// imports the plugin; nothing else may.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // Not readonly: it starts false and is corrected once, by _probe() below —
    // a plain false default until proven otherwise is the honest "assume the
    // optional thing is absent" contract every other blocker() in this shell
    // follows (WallpaperEngine, NightLight, Discord's press blockers).
    property bool available: false
    // Distinguishes "checked, and it's not there" from "hasn't checked yet" —
    // callers that want to avoid a one-frame flash of the fallback while the
    // (synchronous, so this is really just "before Component.onCompleted runs")
    // probe resolves can gate on this instead.
    property bool checked: false
    // …and whether that plugin draws the cookie field in the material (MorphCookieProbe): false for
    // one built before BlobGroup.cookies existed — then the cookies stay QML windows (services/Drift).
    property bool cookies: false

    // ── The blob's join geometry, in ONE place ────────────────────────────────
    // caelestia's border.smoothing default, verified in their
    // plugin/src/Caelestia/Config/borderconfig.hpp. BlobBarLayer hands it to the
    // BlobGroup; BarDock sizes its stroked fillet arc from it. Two copies of this
    // number is two shapes that disagree about where the join is.
    readonly property real smoothing: 20

    // A smooth-min blend of parameter k reaches roughly k/2 out from the contact
    // point, so that is where the outline has to curve. Get it wrong and the
    // stroked arc cuts across the middle of the blob's own fill rather than
    // bounding it — a line drawn through solid material.
    readonly property real filletRadius: root.smoothing / 2

    Component.onCompleted: root._probe()

    function _probe() {
        const comp = Qt.createComponent(Qt.resolvedUrl("../components/blob/MorphProbe.qml"))
        root._resolve(comp)
    }

    function _resolve(comp) {
        if (comp.status === Component.Ready) {
            root.available = true
            root.checked = true
            const probe = Qt.createComponent(Qt.resolvedUrl("../components/blob/MorphCookieProbe.qml"))
            root.cookies = probe.status === Component.Ready
            probe.destroy()
            comp.destroy()
        } else if (comp.status === Component.Error) {
            // Expected on any machine that hasn't built the plugin — not an
            // error worth a console warning, the same way a missing optional
            // binary elsewhere in this shell is just a disabled control.
            root.available = false
            root.checked = true
        } else {
            // Component.Loading — QML resolves a local, already-compiled module
            // synchronously in practice, but the API is async-capable, so this
            // is the correct way to wait rather than assuming.
            comp.statusChanged.connect(function() { root._resolve(comp) })
        }
    }
}
