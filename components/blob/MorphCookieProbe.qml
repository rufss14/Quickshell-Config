import QtQuick
import Quicktest.Blobs

// ── MorphCookieProbe ──────────────────────────────────────────────────────────
// Does the INSTALLED plugin draw the cookie field (BlobGroup.cookies, 2026-10-17)? A plugin built
// before that has the module but not the property, and assigning it would make BlobBarLayer fail
// to load — taking the material with it while every welded card had already stopped painting its
// own fill. So state/Morph.qml asks this, the same catchable way it asks MorphProbe, and the shell
// only hands the material to the blob (Drift.inBlob) when the answer is yes. Until the plugin is
// rebuilt, nothing changes. One of three files allowed to import the plugin (with MorphProbe and
// BlobBarLayer).
// ─────────────────────────────────────────────────────────────────────────────
BlobGroup {
    cookies: []
    cookieStroke: 1
}
