import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"
import "../services"

// ── AiMark ────────────────────────────────────────────────────────────────────
// The current AI provider's mark, at whatever size you ask for.
//
// ── Resolved from the icon theme, never vendored ──────────────────────────────
// These are other people's trademarks and this config is published, so nothing is
// shipped: `Ai.mark` asks the icon theme and returns "" when that provider's icon is
// not installed. Same rule — and the same reason — as WallpaperEngine.logoFile
// reading Steam's mark out of Steam's own cache.
//
// The fallback is therefore the NORMAL case on a machine that has never installed the
// desktop app: a palette-tinted disc with the provider's initial. It is deliberately
// not an approximation of the logo, because a near-copy of a trademark is worse than
// an honest letter.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property int  size: 22
    property real dim:  1.0

    implicitWidth:  root.size
    implicitHeight: root.size
    opacity: root.dim

    // ── Claude is drawn, not resolved ─────────────────────────────────────────
    // Asked for by name: hardcoded, orange, no background plate. Every other provider
    // still resolves from the icon theme and falls back to a letter — see markFor().
    readonly property bool isClaude: Ai.provider === "claudecode"
                                     || Ai.provider === "anthropic"

    ClaudeGlyph {
        id: staticMark
        anchors.fill: parent
        visible: root.isClaude && !Ai.busy
    }

    // While it is answering: the animated burst, in the same orange (ClaudeGlyph's own
    // named constant — the one place that colour is allowed to live).
    ClaudeBurst {
        anchors.fill: parent
        visible: root.isClaude && Ai.busy
        playing: Ai.busy
        tint: staticMark.claudeOrange
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // Only behind the letter. A real icon brings its own shape and background,
        // and a disc drawn under it would read as a badge stuck on top of one.
        visible: !root.isClaude && Ai.mark === ""
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.20)

        StyledText {
            anchors.centerIn: parent
            text: Ai.letter
            variant: "micro"
            font.bold: true
            color: Colors.of(QsWindow.window).primary
        }
    }

    // ── Flattened to the palette ──────────────────────────────────────────────
    // App icons are full-colour marks on their own background plate, which next to a
    // wallpaper-derived palette reads as a sticker rather than as part of the shell —
    // and this repo's rule is that colour comes from `Colors`. So the icon is used for
    // its SHAPE and recoloured: the silhouette still identifies the provider, and the
    // colour belongs to the shell.
    //
    // `MultiEffect.colorization` rather than a shader of our own — it is the supported
    // path and it composites in one pass with the mask below.
    Item {
        id: iconHost
        anchors.fill: parent
        visible: !root.isClaude && Ai.mark !== ""
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Colors.of(QsWindow.window).primary
            brightness: 0.0
        }

        Image {
            id: iconImg
            anchors.fill: parent
            source: Ai.mark
        // Rendered at the real device size rather than scaled from whatever the theme
        // happened to store — a 256px PNG resampled to 22 by the scene graph is
        // visibly softer than one decoded at 22.
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }
    }
}
