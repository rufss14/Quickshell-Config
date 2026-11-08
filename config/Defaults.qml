pragma Singleton
import Quickshell

// ── Defaults ──────────────────────────────────────────────────────────────────
// The two raw constants that both Tokens and Config need, pulled out to break a real
// dependency cycle.
//
// Tokens' own header says it plainly: "Tokens must never import Config — the tokens
// are what the defaults are DEFINED as, so the dependency only runs one way." That
// held with zero exceptions until Tokens started scaling its own families off
// Config's new appearance prefs (fontScale, radiusScale, surfaceOpacity — see
// Tokens.qml). Two of Tokens' properties were ALSO being read back by Config as ITS
// OWN defaults: `radiusWidget` (Config.widgetRoundness) and `surfaceOpacity`
// (Config.barOpacity). Left in Tokens, that's `Config.radiusScale → Tokens.radiusWidget
// → Config.widgetRoundness` — not literally circular (radiusScale doesn't depend on
// widgetRoundness), but it puts a user preference and a scaled design token in the same
// file pretending to be an independent baseline, which is exactly what the "never
// import Config" rule exists to keep clean.
//
// `radiusWidget` moved here for the reason above. `surfaceOpacity` also lives here,
// and now takes its value from the shared blend.lua (Blend.v.active_opacity) — a
// translucent panel lets through the same amount of wallpaper as a translucent
// window. `barHeight`/`barMargin`/`borderChrome`/`borderWidth` stay in Tokens;
// `radiusCard`/`borderChrome` read Blend directly from there.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property int  radiusWidget:   28
    readonly property real surfaceOpacity: Blend.v.active_opacity
}
