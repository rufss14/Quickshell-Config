import QtQuick
import "../config"
import "../services/icons.js" as IconMap

// ── MaterialIcon ──────────────────────────────────────────────────────────────
// One icon, addressed by NAME rather than by codepoint: `MaterialIcon { name:
// "close" }`.
//
// The name is a lookup key into services/icons.js, which gives its codepoint in
// Quicktest Symbols — the shell's OWN cut of Material Symbols, in assets/fonts/.
// No icon font has to be installed. (It used to be the ligature: the name was the
// text and the system font's `rlig` turned it into the glyph. A codepoint needs no
// shaping feature, and the cut font no longer carries the letters at all.)
//
// ── Why a component and not a StyledText variant ──────────────────────────────
// Three reasons, any one sufficient: it needs a FAMILY switch that prose must
// never inherit; it needs a `font.variableAxes` map that would be meaningless on
// body text; and `variant: "icon"` would leave `text:` holding a value that is
// not text, which every wrapping, eliding and accessibility path would then be
// wrong about.
//
// ── The fill axis is the whole point ──────────────────────────────────────────
// This is the caelestia behaviour worth having: an icon does not SWAP when its
// state changes, it fills. The notification bell goes from outline to solid as
// do-not-disturb turns on, animated, instead of cutting to a different glyph.
// That is one axis value, not two icons.
//
// ── Three faces, picked per icon ──────────────────────────────────────────────
// A name (or a glyph that maps to one) draws from Tokens.fontSymbols. A glyph with
// no Material twin — a brand mark — draws from Tokens.fontGlyphs, the bundled cut
// of the Nerd Font, exactly as it looked before. Anything else (plain text handed
// to `glyph`) is prose, in the prose face.
// ─────────────────────────────────────────────────────────────────────────────
StyledText {
    id: root

    // A Material Symbols ligature name — "close", "search", "volume_up".
    property string name: ""

    // ── …or the Nerd Font glyph the shell spelled before ──────────────────────
    // `glyph: "\u{F0349}"` is translated through icons.js (NAME) to `search`, so the
    // ~750 places that already hand an icon around as a glyph — a ternary of two, a
    // field of a service's table, a Section's `glyph:` — become Material icons without
    // anyone resolving each by hand. `name` wins when both are set.
    //
    // A glyph that doesn't map (a brand mark: Material Symbols has none; or plain
    // text) is drawn exactly as it always was, from the bundled glyph face. Never
    // blank, never an English word.
    property string glyph: ""
    readonly property string _name: root.name !== "" ? root.name : IconMap.nameOf(root.glyph)
    readonly property bool _symbol: root._name !== ""

    // 0..1 along the FILL axis. Animatable, and animating it IS the effect.
    property real fill: 0

    // GRAD and opsz are pinned inside the bundled file (see Tokens), so weight is
    // the only other axis there is to set.
    property int weight: Tokens.symbolWeight

    // ── Assignments, never redeclarations ─────────────────────────────────────
    // StyledText already declares variant / sizeScale / emphasis / rich / baseSize.
    // Redeclaring any of them here would be "Property value set multiple times" —
    // a hard load failure of this file that cascades to every file importing it,
    // and one the qmlformat parse check cannot see. PrivacyPill did exactly that
    // with `accent` on an IconButton and took down shell.qml.
    variant: "title"

    // A name the bundled font doesn't carry draws `help` — a visible "no such icon"
    // rather than a blank. scripts/test-icons.js is what keeps that from happening:
    // every name the tree spells must be in the map. A glyph with no name is itself.
    text: root._symbol ? (IconMap.symbol(root._name) || IconMap.symbol("help"))
        :                root.glyph

    font.family: root._symbol ? Tokens.fontSymbols : Tokens.glyphFamily(root.glyph)

    // Empty map off the symbols face: the glyph and prose faces have no variable
    // axes, and handing axis values to a font without them is at best ignored.
    // ── ii's icon drawing ─────────────────────────────────────────────────────
    // Three things make Material Symbols look "clean" at every size, all from the axes:
    //   • the stroke gets sturdier as the icon fills (wght + symbolFillBoost × fill), so a
    //     filled icon isn't a thinner drawing of the same shapes;
    //   • `opsz` follows the pixel size (the font's own optical sizing: big icons are drawn
    //     lighter, small ones sturdier). The bundled cut only carries that axis after
    //     `scripts/material-symbols-map.py --emit` is run once with opsz unpinned; before
    //     that the value is ignored, which is harmless;
    //   • hinting is off — an icon is a drawing, not text, and hinting snaps its curves.
    //
    // FILL is quantised to tenths for the axis. Qt builds a font engine per distinct axis
    // combination, so a fill animation sweeping continuously (and now weight with it) would
    // create dozens of engines per icon; eleven steps per size is a bound. ii does the same
    // for the same reason ("Reduce memory consumption spikes from constant font remapping").
    readonly property real _fillStep: Math.round(root.fill * 10) / 10
    // NOT a binding on `font.pixelSize`: `font.variableAxes` is part of the same grouped
    // property, so a binding that reads the font and feeds the font is a binding loop (it was,
    // on every icon in the shell). Kept in step by the handler below instead, which writes only
    // when the number really changes — setting the axes fires fontChanged again, harmlessly.
    property int _opsz: 24
    function _syncOpsz() {
        const v = Math.max(20, Math.min(48, Math.round(root.font.pixelSize)))
        if (v !== root._opsz) root._opsz = v
    }
    onFontChanged: root._syncOpsz()
    Component.onCompleted: root._syncOpsz()
    font.hintingPreference: Font.PreferNoHinting

    font.variableAxes: root._symbol
        ? ({ "FILL": root._fillStep,
             "wght": Math.round(root.weight + Tokens.symbolFillBoost * root._fillStep),
             "opsz": root._opsz })
        : ({})

    Behavior on fill {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }
}
