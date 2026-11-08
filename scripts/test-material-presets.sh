#!/usr/bin/env bash
# ── test-material-presets.sh ──────────────────────────────────────────────────
# services/MaterialPresets.qml — saved Material Wallpaper looks, and the lock that links a look to a
# colour scheme (the look loads when the scheme is applied). The service is QML, so it is run for real:
# the repo's own MaterialPresets.qml, materialwall.js and palette.js, in a scratch directory with a
# stub Config and ColorScheme, under Qt's `qml` with the offscreen platform.
#
#     bash scripts/test-material-presets.sh
#
# Safe: touches only a temp dir. Skips (exit 0) without Qt's `qml`.
# ─────────────────────────────────────────────────────────────────────────────
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
qml=/usr/lib/qt6/bin/qml
[ -x "$qml" ] || qml=$(command -v qml || true)
[ -n "$qml" ] || { echo "skipped: no qml"; exit 0; }

d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/config" "$d/services"
cp "$here/services/materialwall.js" "$here/services/palette.js" "$d/services/"
# A Singleton can't be instantiated by a plain file; the harness makes one as an Item.
sed 's/^pragma Singleton$//; s/^import Quickshell$//; s/^Singleton {/Item {/' "$here/services/MaterialPresets.qml" > "$d/services/MaterialPresets.qml"
cp "$here/scripts/test-material-presets.qml" "$d/main.qml"
printf 'singleton ColorScheme 1.0 ColorScheme.qml\nMaterialPresets 1.0 MaterialPresets.qml\n' > "$d/services/qmldir"
cat > "$d/services/ColorScheme.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property var live: ({})
    property var presets: []
}
QML
printf 'singleton Config 1.0 Config.qml\n' > "$d/config/qmldir"
cat > "$d/config/Config.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property string themeMode: "dark"
    property bool wallMaterial: false
    property var wallMaterialSaved: []
    property var wallMaterialLinks: ({})
    property string wallMaterialRole: ""; property string wallMaterialRole2: ""
    property real wallMaterialContrast: 1; property real wallMaterialSoftness: 1; property real wallMaterialSize: 1
    property real wallMaterialBackdrop: 0; property int wallMaterialSeed: 0
    property string wallMaterialStack: ""; property string wallMaterialCentre: ""; property string wallMaterialSide: ""; property string wallMaterialCorner: ""
    property bool wallMaterialMirror: false; property bool wallMaterialDrift: false
    property real wallMaterialDriftSpeed: 1; property real wallMaterialSpin: 0
}
QML
# The stub Config must carry every style key the service reads.
for k in $(grep -o '"wallMaterial[A-Za-z0-9]*"' "$here/services/materialwall.js" | tr -d '"' | sort -u); do
    grep -q "$k" "$d/config/Config.qml" || { echo "FAIL stub Config lacks $k"; exit 1; }
done

out=$(cd "$d" && QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 60 "$qml" main.qml 2>&1)
echo "$out" | sed 's/^qml: //' | grep -E '^(FAIL|EXC|ALL OK|[0-9]+ FAILED)' 
echo "$out" | grep -q 'qml: ALL OK' || { echo "$out" | tail -20; exit 1; }
echo "$(echo "$out" | grep -c 'qml: ok') checks"
