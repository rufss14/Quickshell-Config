import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── PkgRow ───────────────────────────────────────────────────────────────
// One pending package in the peek: a tick (AUR / Flatpak — official can't be ticked, a lone official
// install is a partial upgrade) or its source's dot, the name, FROM → TO with how big a jump it is, and
// — under the pointer — a link to the package's page and a hold toggle that springs in. A held one is
// struck through and carries a pause mark so it still reads as held when the tray is away.
// (Was UpdatePanel's inline `PkgRow`; `host` is the UpdatePanel.)
Item {
    required property var host
    id: pr
    // { pkg, kind } — kind is updatefmt.js bump().
    property var row: null

    readonly property var pkg: pr.row?.pkg ?? null
    readonly property string kind: pr.row?.kind ?? "unknown"
    readonly property string name: pr.pkg?.name ?? ""
    readonly property bool selectable: (pr.pkg?.source ?? "") !== "official"
    readonly property bool picked: host.selected[pr.name] === true
    readonly property bool held:   Updates.isHeld(pr.name)
    readonly property bool loud:   pr.kind === "major" || pr.kind === "minor"

    implicitHeight: Tokens.iconXl + Tokens.spacingXs

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: pr.picked ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.14)
             : prHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }
    HoverHandler { id: prHover }
    TapHandler {
        enabled: pr.selectable
        onTapped: host.toggleSelect(pr.name)
    }

    // The tick, or — for official — the source's dot.
    Item {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        width: Tokens.iconMd
        height: Tokens.iconMd

        MaterialIcon {
            anchors.centerIn: parent
            visible: pr.selectable
            name: pr.picked ? "check_circle" : "radio_button_unchecked"
            fill: pr.picked ? 1 : 0
            font.pixelSize: Tokens.iconMd
            color: pr.picked ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgDim
            scale: pr.picked ? 1 : 0.92
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                }
            }
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
        Rectangle {
            anchors.centerIn: parent
            visible: !pr.selectable
            width: Tokens.spacingSm + 1
            height: width
            radius: width / 2
            color: host.sourceTint(pr.pkg?.source ?? "official")
        }
    }

    // The name gives way to the tray as it springs in.
    StyledText {
        anchors.left: lead.right
        anchors.leftMargin: Tokens.spacingMd
        anchors.right: ver.left
        anchors.rightMargin: Tokens.spacingMd
        anchors.verticalCenter: parent.verticalCenter
        text: pr.name
        variant: "caption"
        opacity: pr.held ? 0.4 : 1.0
        font.strikeout: pr.held
        elide: Text.ElideRight
    }

    // ── Version, how big a jump, or an honest absence ─────────────
    // "from → to" is the whole point of the row — a bare target version tells you nothing a rebuild vs.
    // a real upgrade. Flatpak's `from` can be genuinely empty (nothing tracked yet), so that case still
    // falls back to the target alone rather than printing a dangling arrow. The dot says how big the
    // jump is; major and minor spell it.
    Row {
        id: ver
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingMd + tray.width * tray.pop
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacingSm

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: pr.held
            name: "pause"
            fill: 1
            font.pixelSize: Tokens.iconSm
            color: Colors.of(QsWindow.window).warning
        }
        StyledText {
            id: bumpLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: pr.loud || pr.kind === "new"
            text: pr.kind
            variant: "micro"
            font.bold: true
            color: host.bumpTint(pr.kind)
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Tokens.iconXl * 5)
            readonly property bool hasTarget: (pr.pkg?.to ?? "") !== ""
            text: !hasTarget ? "update available"
                : (pr.pkg?.from ?? "") !== "" ? pr.pkg.from + "  →  " + pr.pkg.to
                : pr.pkg.to
            variant: "micro"
            emphasis: "dim"
            elide: Text.ElideLeft
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.spacingSm
            height: width
            radius: width / 2
            color: host.bumpTint(pr.kind)
        }
    }

    // A link to the package's page, and a hold — a `--ignore` on the next run. No hold for Flatpak:
    // `flatpak update` has no exclude, so a hold there couldn't be honoured.
    HoverTray {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingXs
        anchors.verticalCenter: parent.verticalCenter
        shown: prHover.hovered

        ChipButton {
            symbol: "open_in_new"
            tint:   Colors.of(QsWindow.window).info
            onActivated: Qt.openUrlExternally(UF.pkgUrl(pr.pkg))
        }
        ChipButton {
            visible: (pr.pkg?.source ?? "") !== "flatpak"
            symbol:  pr.held ? "play_arrow" : "pause"
            on:      pr.held
            tint:    Colors.of(QsWindow.window).warning
            onActivated: Updates.toggleHold(pr.name)
        }
    }
}
