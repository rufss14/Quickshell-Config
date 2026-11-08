import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/launcher.js" as Logic
import "../../state"

// ── LauncherRow ───────────────────────────────────────────────────────────────
// One result in the launcher: icon, name with the letters you typed lit, what it is,
// and — on the row Enter will open — a keycap saying so. Kinds (`modelData.kind`):
//   app      the app's icon; pin button; drag the icon onto the dock
//   action   a shell action (services/ShellActions): its symbol, a state chip for a
//            toggle (On/Off), and its blocker in place of the description
//   setting  a settings page or row
//   web      `yt cats`: a site's search
//   package  the `+` mode (services/Packages): "Installed" or where it comes from
//   clip     the `;` mode: something you copied
//
// ── M3E: the row does not draw its own selection ──────────────────────────────
// The selected row is a tonal plate that GLIDES between rows on a spring (AppLauncherPanel
// owns it, behind the delegates), so this row only reads `current` and re-colours: its text
// goes onto `primaryContainer`, its tile (a squircle) turns into a cookie on the accent.
// A resting pointer selects nothing (see HoverHandler), so hover needs no fill of its own.
//
// ── It arrives on a spring ────────────────────────────────────────────────────
// A row that is NEW (typing keeps the ones that still match — the model is keyed by id)
// lifts in: opacity on an effects spring, a small rise and scale on a spatial one, each row
// a hair after the one above (Motion.stagger, capped). Animations off: it is simply there.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: row

    // { kind, id, name, ranges, generic, … } from Launcher.search() / the `+` rows.
    required property var modelData
    required property int index

    // Is this the row Enter opens?
    property bool current: false
    property bool pinned: false
    // Pixel size of the app icon; the row's own height is the host's call.
    property int iconPx: Tokens.iconXl

    signal activated()
    // The pointer actually moved onto this row — see the HoverHandler.
    signal pointed()
    signal pinToggled()
    // Right-click: this row's quick actions.
    signal menuRequested()

    readonly property var c: Colors.of(QsWindow.window)
    readonly property string kind: row.modelData.kind ?? "app"
    readonly property bool isApp: row.kind === "app"
    readonly property string iconPath: row.isApp ? Icons.pathForAppId(row.modelData.id) : ""

    // An action that can't run says why in place of what it does.
    readonly property string blocker: row.kind === "action" ? ShellActions.blockerOf(row.modelData.action) : ""
    // The chip at the end: a toggle's state, or a package's standing.
    readonly property string chip:
          row.kind === "action"  ? ShellActions.stateOf(row.modelData.action)
        : row.kind === "package" ? (row.modelData.pkg.installed ? "Installed"
                                    : row.modelData.pkg.source === "aur" ? "AUR" : row.modelData.pkg.repo)
        : ""
    readonly property bool chipOn: row.chip === "On" || row.chip === "Recording" || row.chip === "Muted"
                                   || row.chip === "Hidden" || row.chip === "Installed"

    // Text on the plate (primaryContainer) vs on the card.
    readonly property color nameColor: row.current ? row.c.fgOnPrimaryContainer : row.c.fg
    readonly property color subColor:  row.blocker !== "" ? row.c.warning
        : row.current ? row.c.alpha(row.c.fgOnPrimaryContainer, 0.85) : row.c.fgDim
    readonly property color hitColor:  row.current ? row.c.fgOnPrimaryContainer : row.c.primary

    // How far it has arrived, 0..1 (the host's group header rides the same value).
    readonly property real appeared: fade.value

    // ── Arriving ──────────────────────────────────────────────────────────────
    SpringValue { id: fade; spec: Motion.springEffects; epsilon: 0.002 }
    SpringValue { id: lift; spec: Motion.springSpatial; epsilon: 0.002 }
    Timer {
        id: arrive
        interval: Math.min(row.index * Motion.stagger, Motion.staggerCap)
        onTriggered: { fade.target = 1; lift.target = 1 }
    }
    // Always through the timer, even for the first row (interval 0 = the next turn of the
    // event loop): a SpringValue starts AT its target when it finishes loading, so a target
    // set from this Component.onCompleted could land before that and never animate.
    Component.onCompleted: arrive.start()
    opacity: Math.max(0, Math.min(1, fade.value))
    scale: 0.94 + 0.06 * lift.value
    transform: Translate { y: (1 - lift.value) * Tokens.spacingLg }

    // The icon swells a little when it is the one you are on.
    SpringValue {
        id: swell
        spec: Motion.springSpatialFast
        target: row.current ? 1.1 : 1
        epsilon: 0.001
    }

    // ── Hover selects only when the pointer MOVED ─────────────────────────────
    // Results re-flow under a resting cursor as you type, and Qt re-delivers hover to
    // whichever row is now beneath it. Letting that select would move Enter onto an app
    // you never pointed at. A re-delivery carries the same scene position; a real move
    // doesn't.
    HoverHandler {
        id: hover
        property real lastX: -1
        property real lastY: -1
        onPointChanged: {
            const p = hover.point.scenePosition
            if (p.x === hover.lastX && p.y === hover.lastY) return
            hover.lastX = p.x
            hover.lastY = p.y
            row.pointed()
        }
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: row.activated()
    }
    // Right-click opens the quick actions (Tab does too); the pin button beside it pins.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: row.menuRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingLg

        // ── The icon: drag it onto the dock to pin it there ───────────────────
        // The ICON, not the row: a vertical drag on the row still scrolls the list. The
        // handler takes the grab over from the list once it starts; the dock (same
        // window) draws the icon under the pointer and opens a gap for it — see
        // UiState.beginAppDrag and DockHost.
        Item {
            Layout.preferredWidth:  row.iconPx
            Layout.preferredHeight: row.iconPx
            Layout.alignment: Qt.AlignVCenter
            scale: swell.value

            DragHandler {
                id: appDrag
                target: null
                enabled: Config.dockEnabled && row.isApp
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onActiveChanged: {
                    if (appDrag.active) UiState.beginAppDrag(row.modelData.id)
                    else                UiState.endAppDrag(true)
                }
                onCentroidChanged: {
                    if (!appDrag.active) return
                    UiState.moveAppDrag(appDrag.centroid.scenePosition.x,
                                        appDrag.centroid.scenePosition.y)
                }
            }

            Image {
                anchors.fill: parent
                visible: row.iconPath !== ""
                source:  row.iconPath
                sourceSize: Qt.size(row.iconPx * 2, row.iconPx * 2)   // 2× for HiDPI
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
            }

            // Not an app (or an app with no icon): a tonal squircle that becomes a cookie on
            // the accent when it is the selected one. A letter, not a fallback icon NAME: a
            // name that isn't in the theme just trades one missing icon for another.
            MorphShape {
                anchors.fill: parent
                visible: !row.isApp || row.iconPath === ""
                shape: row.current ? "cookie9" : "squircle"
                fillColor: row.blocker !== "" ? row.c.surfaceContainer
                         : row.current ? row.c.primary : row.c.primaryContainer
                Behavior on fillColor { ColorAnimation { duration: Motion.respond } }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: !row.isApp
                    name: row.modelData.symbol ?? "settings"
                    color: row.blocker !== "" ? row.c.fgDim
                         : row.current ? row.c.fgOnPrimary : row.c.fgOnPrimaryContainer
                    font.pixelSize: Math.round(row.iconPx * 0.58)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: row.isApp
                    text: (row.modelData.name || "?").charAt(0).toUpperCase()
                    variant: "title"
                    font.bold: true
                    color: row.current ? row.c.fgOnPrimary : row.c.fgOnPrimaryContainer
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            // The name comes from a .desktop file — somebody else's string — so it goes
            // through highlight(), which escapes it, before it is allowed to be markup.
            StyledText {
                Layout.fillWidth: true
                rich: true
                text: Logic.highlight(row.modelData.name, row.modelData.ranges,
                                      '<font color="' + row.hitColor + '"><b>', "</b></font>")
                variant: "body"
                color: row.nameColor
                font.weight: row.current ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.blocker !== "" ? row.blocker : row.modelData.generic
                variant: "caption"
                color: row.subColor
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
        }

        // A toggle's state / a package's standing.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: row.chip !== ""
            implicitWidth: chipText.implicitWidth + Tokens.spacingMd * 2
            implicitHeight: chipText.implicitHeight + Tokens.spacingXs * 2
            radius: height / 2
            color: row.chipOn ? row.c.primary
                 : row.current ? row.c.alpha(row.c.fgOnPrimaryContainer, 0.14) : row.c.surfaceContainer
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            StyledText {
                id: chipText
                anchors.centerIn: parent
                text: row.chip
                variant: "caption"
                font.weight: Font.DemiBold
                color: row.chipOn ? row.c.fgOnPrimary : row.nameColor
            }
        }

        // Pinned (always shown) or "pin me" (on the lit row). Pins are the dock's, and
        // pinned apps sort first among equal matches.
        PanelButton {
            visible: row.isApp
            Layout.alignment: Qt.AlignVCenter
            variant: "ghost"
            accent: row.c.primary
            symbol: "keep"
            symbolFill: row.pinned ? 1 : 0      // filled = pinned: one icon, one axis
            glyphTint: row.pinned ? row.c.primary : row.current ? row.c.fgOnPrimaryContainer : row.c.fgMuted
            implicitWidth:  Tokens.fieldHeight - Tokens.spacingMd
            implicitHeight: implicitWidth
            opacity: row.pinned ? 1.0 : (row.current ? 0.7 : 0.0)
            enabled: row.pinned || row.current      // an invisible button must not take clicks
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            onActivated: row.pinToggled()
        }

        // What Enter will do, on the row it will do it to. Always laid out (its opacity
        // moves, its width doesn't), so the text never shifts as the plate arrives.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  cap.implicitWidth + Tokens.spacingMd * 2
            implicitHeight: cap.implicitHeight + Tokens.spacingXs * 2
            radius: Tokens.radiusXs
            color: row.c.alpha(row.c.fgOnPrimaryContainer, 0.14)
            opacity: row.current ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            MaterialIcon {
                id: cap
                anchors.centerIn: parent
                name: "keyboard_return"
                variant: "caption"
                color: row.c.fgOnPrimaryContainer
            }
        }
    }
}
