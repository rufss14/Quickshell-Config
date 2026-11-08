# assets/fonts — the shell's own fonts

Every icon the shell draws comes from one of the two icon files, and its default
prose face is the third, all loaded by `config/Tokens.qml`. No font has to be
installed, and no package upgrade can change these: they only change when this
repo does.

| File | Family | What's in it |
|---|---|---|
| `GoogleSansFlex.ttf` | Google Sans Flex | the default prose face (`Tokens.fontUi`): **unmodified** upstream file, variable (ROND, opsz, slnt, wdth, wght); from <https://github.com/google/fonts/tree/main/ofl/googlesansflex> (2026-10-31). Not generated: replace it with a newer upstream file as-is. |
| `QuicktestSymbols.ttf` | Quicktest Symbols | the Material Symbols (Rounded) the tree names; FILL, wght and opsz kept as live axes (opsz is set per icon from its size), GRAD 0 pinned |
| `QuicktestGlyphs.otf` | Quicktest Glyphs | every Nerd Font codepoint the tree spells: brand marks, Codicons, Font Awesome, MDI glyphs still drawn as glyphs |

**The two Quicktest files are generated — do not edit by hand.** Both are cut, together with
`services/icons.js`, by:

```sh
python3 scripts/material-symbols-map.py --emit
```

It reads the full fonts from the machine that runs it (`fc-match`, or
`--symbols-font` / `--nerd-font`), so only the person regenerating needs them:
`ttf-material-symbols-variable-git` (AUR) or Google's
`MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf`, plus `otf-codenewroman-nerd`,
plus `python-fonttools`. `bun scripts/test-icons.js` fails if a new icon name or
glyph appears in the tree without a regeneration, or if these files and
`icons.js` were not generated together.

After regenerating, restart the shell (ALT+Q), not a hot reload: Qt keeps the old
file registered under the same family name.

## Licences

- **Google Sans Flex** — by The Google Sans Flex Authors, SIL Open Font License 1.1
  (`GoogleSansFlex-OFL.txt`, no Reserved Font Name). "Google", "Google Sans" and
  "Google Sans Flex" are trademarks of Google LLC; the name is kept because the file
  is the original, unmodified font — don't subset or modify it under that name.

The families are renamed because these are modified (subset) fonts.

- **Quicktest Symbols** — subset of Material Symbols by Google,
  <https://github.com/google/material-design-icons>, Apache License 2.0.
- **Quicktest Glyphs** — subset of the icon glyphs patched into CodeNewRoman Nerd
  Font by Nerd Fonts (<https://github.com/ryanoasis/nerd-fonts>, MIT). It carries
  none of Code New Roman's own letterforms. The glyphs come from these upstream sets:
  - Material Design Icons — Pictogrammers, Apache License 2.0
  - Font Awesome — Fonticons, Inc., SIL OFL 1.1 (font) / CC BY 4.0 (icons)
  - Codicons — Microsoft, CC BY 4.0
  - Font Logos — Unlicense
  Brand marks remain the trademarks of their owners.
