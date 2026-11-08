import QtQuick
import Quicktest.Blobs

// ── MorphProbe ────────────────────────────────────────────────────────────────
// The ONLY file in this repo allowed to `import Quicktest.Blobs`. state/Morph.qml
// loads this through Qt.createComponent (never a direct import, never a Loader
// with an eagerly-active source) specifically so a missing plugin fails as a
// catchable Component.Error instead of taking down whatever imported it.
//
// Referencing BlobsInfo.stage1 rather than leaving the import unused means a
// stray future edit that deletes the real content but leaves the import behind
// still fails this probe honestly, instead of reporting "available" for a module
// that no longer does anything.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    readonly property bool ok: BlobsInfo.stage1
}
