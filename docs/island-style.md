# Island style

The quality bar for everything under the bar: the three islands (`modules/island/`, `config/islands.js`) and the
panels that stand on them. The wallpaper page is the reference implementation, because it was taken through eleven
rounds of the user's own judgement (2026-11-14). Read it as a record of what was rejected and why, so the next page
starts where that one ended and not where it began.

The colour scheme page (`modules/panels/ColorSchemePanel.qml`, `modules/panels/colorscheme/`) is the second
reference: it is the same recipe with a different subject (a loud card that draws the thing being edited, a source
rail, cards that are miniatures, option cards, hover tools, a loud Apply pill).

The short version: **a page that looks like a settings form is wrong.** The user wants a premium, expressive,
Material 3 Expressive page that is also correct. Both. "It works and uses the tokens" is the floor, not the goal.
The static checks passing means no typos, never that the page is good.

The Audio Mixer (`modules/panels/EqualizerPanel.qml`, `modules/panels/mixer/`) is the third: the loud card is the output, the
cards are channels and devices, and a card's options unfold inline under it.

The overview (`modules/overview/`, `modules/hud/`) wears the same recipe on `components/GroundCard` instead of an island face (2026-11-17).

Shared parts to reuse, not copy: `components/SourceRail`, `OptionCard`, `CardTool`, `LitTool` (a tool with a lit state and a
tip), `GroupHeader`, `SearchPill`, `MorphShape`, `StateLayer`, `ChipButton`, `ValueSlider { expressive: true }`.

Reference files: `modules/panels/WallpaperPanel.qml` (the page), `modules/panels/wallpaper/` (`WallpaperCard`,
`WallpaperNow`, `WallpaperSources`, `WallpaperMaterial` + `WallpaperMaterialPlate`,
`WallpaperBrowse`), `modules/island/IslandDock.qml` (open and close), `IslandRail`, `IslandPlate`.
Mechanics and palette rules stay in `docs/standards.md`; this file is about how things should look and feel.

## 1. Tone: a ladder of flat plates

Surfaces are flat tonal fills, stacked one tone at a time. No outlines on cards, no gradients, no drop shadows
inside a page.

- The island's own face (the blob's `frameFill`) is the ground.
- `section` is a plate on that ground: a page's big areas, the gallery, the drawer.
- `surfaceHigh` is a card lifted on a plate: a picture's canvas, an option card that is off, a Material plate.
- `primaryContainer` is the one loud card of a region (the hero, the chosen row, a chosen option) with
  `fgOnPrimaryContainer` text and `alpha(fgOnPrimaryContainer, 0.72)` for the second line.
- `primary` is for the single focal object on the loud card (a badge, the Apply pill), `fgOnPrimary` on it.
- A hairline (`Tokens.borderWidth`, `outline`) is allowed on a picture's canvas and a keycap. Nowhere else.

Radii: `radiusCard` for cards, `radiusXl` for the hero and the big plates on the island, `radiusSm` for rows, and a
full pill (`height / 2`) for chips and anything chosen. Concentric corners: an inner radius is the outer one less the
gap, never a small radius inside a large one.

## 2. Shape: M3E, and a choice that changes shape

- Badges are `MorphShape`. Off, a badge is a plain disc (`circle`); on, it blooms into a shape of its own
  (`cookie9`, `clover`, `sunny`, `squircle`) on a spring. Give each sibling a different shape.
- A chosen card goes rounder: its radius runs from `radiusSm` to `height / 2` on a spring (`OptionCard`),
  or from `radiusCard` to `radiusXl` (the gallery's cards under the pointer).
- Big shapes may run past a card's edge if the card is a `ClippingRectangle` (a plain `Rectangle { clip: true }`
  cuts a square corner on a rounded card). Calm shapes only on hover: the spiky `burst` was rejected as a hover
  state; `squircle` and `cookie9` are fine.
- A mark that says "this one" is a shape with a tick (the card on screen), not a caption.

## 3. Motion

Every move is a spring (`SpringValue`, `Motion.spring*`) or a `Motion` duration with a `Motion` curve. Raw
`Easing.*` is drift. Reduced motion is central: gate any new decorative loop on `Motion.ambientOn`; a busy spinner
is exempt. `scripts/check-qml-hotpaths.py` is gated at zero.

- **Boxes do not wobble.** A big surface (the island, a drawer) uses the spatial spring with damping 1 (critically
  damped). One percent of overshoot on a 412 px card is six pixels, and reads as a wobble. Small selections (a
  pill sliding between rows, a badge) may overshoot a little, as M3E does.
- **Nothing in an island's opening goes back the way it came** (2026-11-15, the user: "it drops down and then a
  bit up"). The blob's velocity deform is an underdamped spring, so the island lobes have it off
  (`deformScale: 0` in `BlobBarLayer`), and the page arrives in the direction the card grows (`IslandCard`), not
  against it.
- **One spring starts too hard.** An opening that is one critically damped spring was "too abrupt" (it starts with
  its hardest push). Chain two: the box follows a point that travels with the reveal spring on a stiffer spring
  (`IslandDock.followSpec`). That is an S curve.
- **Content arrives after its box and leaves before it.** In, contents fade once the box is a third open. Out, they
  are gone in the first tenth of the movement and then the empty box shrinks. Contents cropped line by line by a
  shrinking box read as broken.
- **A lobe comes out of its strip, a spring starts from rest, a page is unloaded at rest** (2026-11-15, all in
  `IslandDock` / `SpringValue`): the blob rect starts tucked inside the frame (`tuck`), or it pops out by a few
  pixels in one frame and snaps away at the end; a spring's first two frames never count a long frame in full
  (`_warm`), or an opening that loads a heavy page begins half open; the card is dropped only when every spring
  has stopped (`_drop`). On closing the contents' fade is not tied to the box at all: it runs at once, on
  `springEffectsFast`.
- Cascades: `PopIn` with an `index` (and a `cap`), so cards arrive one after another, not together.
- Hover leans a card to 1.03 and a press dips it to 0.95 to 0.96, on `Motion.springSpatialFast`. `StateLayer` for
  the wash. A thing that just changed state answers with a bump (a bookmark taken pops to 1.5 and settles).
- A sliding indicator (`WallpaperSources`, `IslandRail`) beats three cards that each light up: one filled pill that
  travels between the rows is the island's idiom.

## 4. Never show the bad thing first

If a better version of something is on its way, show a loading state, not a worse version that is then swapped for
the good one. The hero used to show a scene's low-quality GIF and then jump to the video; it now shows a turning
cookie until the real first frame is up (with a 12 s or error fallback to the GIF). The same applies to a picture
that decodes slowly (a cookie on the card's tone), a list that is empty because it is still reading, a value that
is a placeholder. Make the wait look intended.

## 5. Controls

- **No popups for options.** A floating popover over a gallery "feels off" (user). Options open INLINE as a drawer
  in the column (`drawer` in `WallpaperPanel`: critically damped height, the gallery gives way), so the effect of
  a filter is visible while you set it. A secondary view is a view with Back, not a floating card.
- **Choices are cards, not chips.** A group of options is a row of `OptionCard`s: a badge, a label, a
  detail line when there is something to say. `ChipButton` (`tonal: true` for a quiet plate while off) is for tools
  in a grid and small actions; a `ChipRow` of text pills is for a short list of values (15 min, 30 min).
- **Tools appear under the pointer.** Per-item actions are a capsule at the corner that opens on a spring on hover
  (`CardTool`), big enough to hit (`iconXl`), with a small persistent mark for a state that matters (a
  bookmark). Pointer-only tools also need a keyboard route.
- **Destruction is confirmed on a layer, not by re-pressing in place.** Delete lays a Keep / Remove layer over the
  item; arming the same button and asking the user to read a label that moved under their pointer was replaced.
- **Hit areas**: use a `MouseArea` for a button that sits over another clickable (a `TapHandler`'s passive grab lets
  the press fall through to the item below).
- **The search field is a feature, not a box.** It types its own hints while idle (`TypedPlaceholder`, shared with
  the launcher and the settings), shows what it understands (a colour's name), offers swatches while focused,
  says "3 of 13" while it has text, and reacts to every key. A bare text field was rejected as "boring".
- **A file picker is a destination**: places, a path you can press, big thumbnails, a floating Add capsule
  (`WallpaperBrowse`). Not a list of file names.
- **Tooltips**: a `HoverTip` is parented to its control, so it is clipped by any clipping ancestor and painted
  under later siblings of its row. Give the row a `z`, right-align a tip at the edge (`alignEnd`), and put no tip
  inside a `ClippingRectangle` (use the accessible name).

## 6. Text

- Sentence case, short, in the user's voice. **No dashes as punctuation in UI text** (no " - ", no em dash): the
  user finds them "AI like". Use a full stop, a colon or a comma. A middle dot (`·`) between two facts is fine.
- Numerals that matter are large (`Tokens.fontDisplay`, `font.features: { tnum: 1 }`), with the name small under
  or beside them. A status that stands where a number would (Material's On / Off) takes the same place.
- UI strings go through `Translation.tr()` with `%1` placeholders, not concatenation, in new code.

## 7. Layout

- A page declares its size in `config/islands.js` (`body: { w, h }`) and fills it. The page has no header: the rail
  says where you are.
- **Hold an aspect with minimum, maximum and preferred.** A preferred height alone is shrunk with its siblings when
  the column runs short. The wallpaper hero is 16:9 because it sets all three, and the cards around it were made
  compact enough to fit.
- Fewer, bigger things beat many small ones: two gallery columns, not three. Scrolling a little is better than a
  page you cannot judge a picture on.
- A tall settings page is a scroll of plates with a title row each (`WallpaperMaterialPlate`: a small shape badge,
  a title, a note), not a segmented switch hiding four pages. Keep the live preview in view while the controls scroll.
- Every picture sits on a canvas (a lifted plate with a hairline); the one that is on screen wears the accent as
  that canvas.

## 8. Icons and colour

- Icons come from the shell's own fonts only. A glyph that is not in `services/icons.js` is a help-circle. **Never
  run `scripts/material-symbols-map.py --emit`**: the user reverted it once. Check the name in `icons.js` first
  (`favorite` and `heart` are not there; `bookmark`, `star`, `close`, `check`, `delete_forever` are).
- Colours come from `Colors.of(QsWindow.window)`. The sanctioned hardcoded colours are four kinds in
  `docs/standards.md`; the wallpaper search's eight hue swatches are the "picker's input" kind.
- A destructive confirm may use `danger` and `fgOnPrimary`; `danger` shares a hue with `primary` in some
  palettes, so it never carries meaning alone (an X, a word).

## 9. How a page gets built here

1. Read this file, `docs/standards.md`, `docs/qml-api-caution.md` and the feature doc for the area.
2. Read the existing page and keep what the user liked. They prefer an existing rich panel re-laid for the island
   over a simplified new one (2026-11-13); simplify only when asked.
3. Build in stages and screenshot each (recipe below). Judge the screenshot as the user would: is anything plain,
   cramped, empty, clipped, or "boring"? Fix it before reporting.
4. Run the checkers in `docs/checks.md`. Put real logic in a `.js` with a test (colour sorting, breadcrumbs, paste
   kinds are examples). Put system work in a service, never in the page.
5. Report what was SEEN and what was not. Hover, click, and animation cannot be driven from here; say so and list
   them for the user.

Screenshot recipe (the user allowed it for this work; ask again in a new task): check
`hyprctl activewindow -j` is not fullscreen, `qs ipc --pid $(pgrep -x qs) call island close`, then
`call island part <page> <part>` (or `call panel toggle <key>`), `sleep` 4 to 7 (thumbnails and videos need it),
`grim -g "40,40 900x470" file.png` (crop to the island only), read it, `call island close`, delete the file. The
pointer cannot be driven and blind input is banned, so no hover shots.

## 10. What the user rejected (do not repeat)

- Source cards with a big badge, then a big number bottom left: rejected twice; the sliding-pill rail replaced them.
- A popup for sort and filter; a popup for parallax.
- A file browser that is a plain grid of names.
- A search field that is only a pill with a placeholder.
- A GIF that is swapped for a video.
- An opening that starts with a single hard spring; a closing that crops its own contents.
- A spiky hover shape on a calm card.
- A tooltip that is cut or covered.
- Dashes in status text.
- Delete that arms in place; a star and a bin that are small and always on the picture.
- A dense four-tab settings page for the Material wallpaper.

When unsure between two designs, make the more expressive one that still reads at a glance, and say what you chose.
