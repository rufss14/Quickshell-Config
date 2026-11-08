pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── DiscordTheme ──────────────────────────────────────────────────────────────
// The Quicktest Discord theme (vencord/quicktest.theme.css) wearing Settings → Type & Shape.
// The palette half of that is the colour wave's (apps-lib.sh); this is the other half: the
// spacing, the corner ladder, the three faces, the motion durations and the shadows.
//
// ── The shell passes RESOLVED values, the script never re-derives them ────────────
// Same reasoning as Cursor.qml. Tokens already applies densityScale / radiusScale, square
// corners, the "Rounder" ladder and the installed-font fallback; Motion applies motionScale
// and collapses to 0 when animations are off. Reading those means the theme cannot
// disagree with the shell about what a card's corner is — a Python copy of that arithmetic
// could, the first time Tokens changed.
//
// ── What does NOT reach Discord, and why ──────────────────────────────────────────
//  - Opacity: the shell's surfaces are translucent over a wallpaper; Discord's cards sit on
//    its own solid frame, so a lower opacity would only dull them.
//  - Text scale: Discord sizes its text in a mix of fixed px and rem it does not tie to the root
//    font size (measured: scaling <html> changed nothing on screen), so there is nothing to bind
//    it to. Its own Appearance → Chat Font Scaling is the only lever.
//  - Icon shape reaches the sidebar entries' holders and the single icon buttons, but not the guild
//    icons: those are masked by an SVG foreignObject that animates its own squircle, and clipping
//    one would fight Discord (docs/discord.md).
//
// ── Inert without the theme ───────────────────────────────────────────────────────
// apply-shape.sh skips a client that has no quicktest.theme.css, and the script writes
// nothing when the values are unchanged (Vencord re-parses a theme on any write), so the
// push at launch costs one short run on a machine that never used this.
//
// ── The font-always-wrong-until-reload gap ──────────────────────────────────────────
// `Component.onCompleted` only fires at SHELL launch, but the theme file can be reset to its
// committed (wrong-font) defaults without the shell restarting at all: theme-setup.sh discord
// re-copies it from the repo any time it's re-run (Setup's "Theme your apps", or a repo pull
// that touched the file). Nothing in THIS singleton's bindings changes when that happens —
// `shape` is a pure function of Tokens/Motion/Config, none of which moved — so `onPayloadChanged`
// never refires either, and Discord keeps showing the repo default until the next full reload.
// Same shape as the "heals at launch" comment above described, just not caught by it.
//
// Fixed the way the palette side already handles this exact gap: apps-lib.sh/theme-setup.sh
// never wait on the shell to re-push colours after a copy, because WAL_COLORS is a file on disk
// they can read and push themselves, synchronously, right after copying. `shape` had no such
// file — it only ever lived in this binding — so theme-setup.sh had nothing to re-push with and
// had to leave it to `Component.onCompleted`. This writes that file: whatever `shape` currently
// resolves to, cached here, so theme-setup.sh's copy step can push it back immediately too,
// exactly like `--colors "$WAL_COLORS"`. Debounced the same as the real push (one write per
// settled burst, not one per frame of a slider drag).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // One decimal is plenty for a shadow and keeps a no-change push byte-identical.
    function _r(v) { return Math.round(v * 10) / 10 }
    function _shadow(elevation) {
        const dp = Tokens.shadowDp(elevation)
        return { y: root._r(Tokens.shadowOffsetY(dp)), blur: root._r(Tokens.shadowBlur(dp)),
                 spread: root._r(Tokens.shadowSpread(dp)) }
    }

    readonly property var shape: ({
        spacing: { xs: Tokens.spacingXs, sm: Tokens.spacingSm, md: Tokens.spacingMd,
                   lg: Tokens.spacingLg, xl: Tokens.spacingXl, xxl: Tokens.spacingXxl },
        radius:  { xs: Tokens.radiusXs, sm: Tokens.radiusSm, pill: Tokens.radiusPill,
                   card: Tokens.radiusCard, xl: Tokens.radiusXl },
        font: Tokens.fontFamily,
        mono: Tokens.fontMono,
        motion: { respond: Motion.respond, fast: Motion.fast, standard: Motion.standard,
                  emphasized: Motion.emphasized, exit: Motion.exit, slow: Motion.slow,
                  // The M3 state-layer wave (Motion.ripple) and the two spring settle times
                  // (Motion.springSettleFast/springSettle) the CSS pairs with its baked spring
                  // curves — see the Tokens section of quicktest.theme.css.
                  ripple: Motion.ripple, "spring-fast": Motion.springSettleFast, spring: Motion.springSettle },
        // Settings → Icon shape: what sits behind a sidebar entry's icon and on a single icon button.
        icon: Config.iconShape,
        // 0 is "shadows off" (Config.shadowScale), not a zero-size shadow.
        shadow: Config.shadowScale > 0 ? { card: root._shadow(Tokens.elevationCard),
                                           popup: root._shadow(Tokens.elevationPopup) } : null
    })
    readonly property string payload: JSON.stringify(root.shape)

    property string lastError: ""
    property bool _again: false

    onPayloadChanged: { debounce.restart(); root._cache.value = root.shape }
    // At launch too: it heals a theme that Setup just re-copied from the repo (defaults).
    Component.onCompleted: { debounce.restart(); root._cache.value = root.shape }

    // theme-setup.sh's own cache of `shape`, so a `discord_setup()` copy can push the CURRENT
    // resolved values immediately rather than wait for this singleton's own launch/change push —
    // see the header comment. Cache, not config: nothing reads it back INTO the shell, it only
    // ever flows shell → file → theme-setup.sh.
    JsonStore {
        id: _cacheStore
        path: Quickshell.cachePath("discord-shape.json")
        defaults: root.shape
        // JsonStore refuses writes until its own file read settles (`ready`), which loses a
        // `value =` set from Component.onCompleted on a fresh profile — nothing re-triggers the
        // write once `ready` catches up, since `value` itself didn't change again. Setting it
        // again here, once loading is actually done, guarantees the cache exists after the very
        // first run rather than only from the second Config/Tokens change onward.
        onLoaded: _cacheStore.value = root.shape
    }
    readonly property alias _cache: _cacheStore

    // A slider commit and a toggle can land together; one run for the burst.
    Timer {
        id: debounce
        interval: 400
        onTriggered: root._run()
    }

    readonly property string script: Quickshell.shellPath("scripts/themes/discord/apply-shape.sh")

    function _run() {
        if (push.running) { root._again = true; return }
        push.command = ["nice", "-n", "10", "bash", root.script, root.payload]
        push.running = true
    }

    Process {
        id: push
        stderr: StdioCollector { id: err }
        onExited: function (code) {
            root.lastError = code === 0 ? "" : (err.text.trim().split("\n").pop() || ("failed (" + code + ")"))
            if (code !== 0) console.warn("DiscordTheme: apply-shape.sh exited", code, "-", err.text.trim())
            if (root._again) { root._again = false; root._run() }
        }
    }
}
