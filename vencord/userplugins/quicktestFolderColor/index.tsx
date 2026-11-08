/*
 * quicktestFolderColor — "Match Colorscheme" on Discord's own Folder Settings modal.
 *
 * quicktest.theme.css can recolour Discord's own CSS variables, but a guild folder's colour
 * isn't CSS at all — it's a value stored in the user's own settings proto (SortedGuildStore /
 * GuildFolderUtils, GUILD_FOLDER_UPDATE) and read back into Discord's native UI. The only way
 * to offer "use the shell's colour" there is from inside that UI, hence a real patch (unlike
 * quicktestMotion, which is deliberately patch-free).
 *
 * The Folder Settings modal (webpack search for "onChange:this.handleColorChange,
 * allowBlackCustomColor", 2026-11-01) is a small class component with everything spelled out,
 * not property-mangled: `handleColorChange = e => this.setState({color: e})` is exactly what
 * every preset swatch in its own colour picker already calls on click — confirmed over CDP by
 * walking a swatch's own React fiber up to the picker's `{value, color, onChange,
 * allowBlackCustomColor}` props and seeing the identical closure source on both. The colour
 * value these swatches pass is a plain decimal int (0x5865f2 === 5793266, the "Default" swatch),
 * not a hex string — so this plugin just calls that same `handleColorChange` with an int of its
 * own, the same entry point a real swatch click uses. Discord's own Done button (handleSubmit,
 * same module) does the actual persisting afterwards, untouched.
 *
 * `--qs-primary` is read directly off <html> rather than piped in some other way: this plugin
 * runs in the same renderer quicktest.theme.css paints, so the CSS variable IS the live value —
 * no IPC, no re-deriving the shell's colour maths (same reasoning DiscordTheme.qml gives for
 * never re-deriving Tokens' arithmetic: one source of truth, read, never recomputed).
 */
import definePlugin from "@utils/types";
import { Devs } from "@utils/constants";

function shellPrimaryColorInt(): number | null {
    const hex = getComputedStyle(document.documentElement).getPropertyValue("--qs-primary").trim();
    if (!/^#[0-9a-f]{6}$/i.test(hex)) return null; // theme not installed/enabled — no value to offer
    return parseInt(hex.slice(1), 16);
}

export default definePlugin({
    name: "QuicktestFolderColor",
    description: "Adds \"Match Colorscheme\" to Discord's own Folder Settings modal, setting the folder's colour to the Quicktest shell's current primary.",
    authors: [{ name: "rufss14", id: 0n }],
    tags: ["Customisation"],
    required: false,
    enabledByDefault: false,

    // No Button export in this Vencord's @webpack/common (checked: src/webpack/common/components.ts
    // has none) — a plain <button> avoids chasing it down through a raw webpack find for one
    // element. Styled off the shell's own accent, same var the modal's own ColorPicker swatches
    // now read nothing from (Discord's dialog CSS, not ours) — this one IS ours, so it wears it.
    renderMatchButton(instance: any) {
        const color = shellPrimaryColorInt();
        if (color == null) return null;
        return (
            <button
                key="quicktest-match-colorscheme"
                type="button"
                onClick={() => instance.handleColorChange(color)}
                style={{
                    marginTop: 8,
                    alignSelf: "flex-start",
                    padding: "6px 12px",
                    borderRadius: 4,
                    border: "1px solid var(--qs-primary)",
                    background: "transparent",
                    color: "var(--qs-primary)",
                    font: "inherit",
                    fontWeight: 500,
                    cursor: "pointer",
                }}
            >
                Match Colorscheme
            </button>
        );
    },

    patches: [
        {
            find: "onChange:this.handleColorChange,allowBlackCustomColor",
            replacement: {
                // The whole "Folder Color" field — a FormItem-ish wrapper (o.D) around the
                // ColorPicker (g) — captured generically on var names (minifier-assigned, not
                // ours to pin) but anchored on the literal prop names, which this build leaves
                // unmangled. Turns its single child into [field, our button].
                match: /(\(0,\i\.jsx\)\(\i\.D,\{label:\i\.intl\.string\(\i\.t\.\i+\),children:\(0,\i\.jsx\)\(\i,\{className:\i\.E,defaultColor:\i\.DO,colors:\i\._tK,value:null!=\i\?\i:\i\.DO,onChange:this\.handleColorChange,allowBlackCustomColor:!0\}\)\}\))/,
                replace: "[$1,$self.renderMatchButton(this)]",
            },
        },
    ],
});
