import QtQuick
import Quicktest.Blobs

// ── MorphGradientProbe ────────────────────────────────────────────────────────
// Does the INSTALLED plugin draw a gradient fill (BlobGroup.gradMid)? A plugin built before it has
// the module but not the property, and assigning one is a load error, so state/Morph.qml asks this the
// same catchable way it asks MorphProbe and MorphCookieProbe, and the Gradient view disables itself with
// a reason until the plugin is rebuilt. One of four files allowed to import the plugin (with MorphProbe,
// MorphCookieProbe and BlobBarLayer).
// ─────────────────────────────────────────────────────────────────────────────
BlobGroup {
    gradMid: 0
}
