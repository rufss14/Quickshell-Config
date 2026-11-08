# quicktest-blobs

A native Qt6 QML module for the panel-morph effect (`modules/panels/ControlCenterWindow.qml`
and, later, the bar). It is **not required** to run this shell — everything degrades to a
plain QML grow/weld animation when this module isn't built, and the shell must never fail
to start because of it.

## Provenance and license

This module's eventual blob-union renderer (`BlobGroup`/`BlobRect`/the SDF shader) is
**adapted from [caelestia-dots/shell](https://github.com/caelestia-dots/shell)**,
`plugin/src/Caelestia/Blobs/`, which is licensed **GPLv3** — see `LICENSE` in this directory
(copied verbatim, as GPLv3 requires). That means everything under `plugin/` is GPLv3, even
though the rest of this repository is not — this is the standard pattern for a GPL'd
component vendored into an otherwise differently-licensed tree (the license applies to this
subtree, on its own).

Stage 1 (the current state) is original, trivial scaffolding (one singleton, no shader) —
it exists to prove the build/install/import pipeline end to end before the real renderer is
ported in.

## Building

```
scripts/build-blobs-plugin.sh
```

Builds and installs the module to `$XDG_CACHE_HOME/quickshell-quicktest/qml` (never a
system path — no `sudo`), and prints the `QML_IMPORT_PATH` entry the shell needs. Nothing
launches this automatically yet; see the script's own comments for the wiring this still
needs (adding that path to how Quickshell is started) before the QML side can rely on it
being present.
