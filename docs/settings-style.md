# Settings style

How the settings app is built, after the overhaul. One document — this replaces
`docs/settings-style.md` (the full-width three-column era) and
`docs/settings-panel-style.md` (the per-page view-strip era), both of which
described systems that no longer exist.

Worked examples: `AppearancePage.qml` (the plain two-column case),
`NetworkPage.qml` (an adaptive hero over cards), `WidgetsPage.qml` (a page that
is a picker, not a form), `StoragePage.qml` (a space map).

---

## 0. The window

`SettingsCard` is the surface; two hosts choose how it appears:

- **`SettingsWindow.qml`** (default) — a `FloatingWindow` xdg-toplevel, floated and
  centred by a rule in `hypr/rules.lua`. It sits below every layer surface, so the
  bar stays on top and interactive. Opens at **1200 × 740** and resets to that size
  on every open.
- **`modules/bar/SettingsPanelHost.qml`** — the same card welded into the frame's
  bottom strip (`Config.settingsPanel`). It lives inside Bar's own window because
  `Quicktest.Blobs` can only fuse shapes sharing one scene graph.

**The page area is about 885 × 650** at the opening size, after the rail, the
margins and the corner cluster (pin star + close cross: the page keeps clear of both). Every number in §6 comes from that.
**That size is the reference** (the user's call, 2026-10-07): every page is laid out to
look right — and, where it can, to end at the window's edge — at 1200 × 740.

Bigger than that (fullscreen), the page column stops at **1280px** and the rest becomes
equal gutters (`SettingsCard` pageArea `maxPageWidth`), for the tab strip, the search
results and every page alike. A bento page goes to three columns past ~930px.

---

## 1. What the look is

The settings app wears the same dialect as the bar's panels (Colours, Clock, Media, Wallpaper):
a flat `section` card, capsule chips and fields, a `SegmentSwitch` for pages, `ChipTray`s for
header actions, springs, and pages that arrive in a short cascade. It used to have its own
(outlined shadowed cards, a scallop chip, "never a capsule") and sat beside three panels in
another; unified 2026-10-26 at the user's request.

- Colours from `Colors`, spacing/type/radii from `Tokens`, durations from `Motion`.
  No literals — see CLAUDE.md. A width that is a layout decision (a rail, a preview
  box) is the exception and gets a named property.
- **One accent per page**, passed to the page's header and its sections. Settings
  uses `Colors.primary` throughout (Wallpaper too — it wore `info` until 2026-10-26);
  `warning`/`danger` are for cards that are actually a warning.

### 1.0 One flat card, and where depth comes from

A `Section` is a plain `Rectangle` filled with **`Colors.section`** — `surfaceContainer`
at `Tokens.sectionAlpha`, the colour the panels put behind a group of controls and (opaque)
the navigation rail's own material. No outline, no cast shadow, no hover lift. It is NOT
tinted per accent: this palette is wallpaper-derived, so a tint lands somewhere different on
every wallpaper and six cards come out as six colours.

Depth comes from the page behind it and from three small things: the heading's icon chip
(the accent's only filled area in the card), `PointerGlow` (a soft light that follows the
pointer across the card and catches the nearest edge — it draws nothing at rest), and the
cascade (§1.3). Nested wells: `elevation: Tokens.elevationCard` is a well inside another card
(the page's own surface), `elevationPopup` is the one that wears an outline; `cardBorder`
is a warning card's own outline.

Dropping `Surface`'s cast shadow also drops ~130 `SurfaceShadow` items from every page.

### 1.2 The chip

A card heading wears the same icon chip as `PanelHeader`: `ShapeBox` — a rounded square, or
whatever single shape `Config.iconShape` asks for (cookie, clover, circle…) — filled with the
accent at 0.20 and stroked at 0.32. `QuickToggleTile`'s chip is the same box. The scallop
(`Scallop`, `ScallopChip`, `CookieButton`) is no longer a settings signature; it is one of the
shapes `ShapeBox` can draw, and `CookieButton` is still the page's one outward-reaching action
where a page has one (Bluetooth's Scan).

### 1.3 Motion: answer the hand, and arrive

What moves, and why each is cheap:

- **Navigation.** The rail's selection is ONE capsule (`navPill` in `SettingsCard`) that
  glides to the page you pick; its leading edge leaves first and the trailing one follows, so it
  stretches and settles. The rail icon fills in (the FILL axis) while its page is current. The
  view strip is a `SegmentSwitch` whose indicator springs between segments. Changing page
  slides the new one in from the side you went to (16px) while the old fades on t² (`PageSlot` A/B).
- **Arriving.** A page you changed TO cascades: each `Section` and `QuickToggleTile` rises
  `spacingMd` and fades in, a stagger of `Motion.stagger * 2` after the one before it, capped at
  six (`ViewEnter`; the stagger is set by the card's place among its siblings). The page a
  window OPENS on appears at once, and so does a card a page builds later (a device that
  appears): `UiState.settingsCascade` is up only while `SettingsCard.showView()` loads the page.
  An earlier, slower rise (`Rise`, 400ms) was removed 2026-10-07 because every page read as slow
  to load; this one is ≤ ~250ms to opaque, and `ViewEnter` makes motion-off an instant swap.
- **Control feedback.** A tile's chip pops when it switches on and dips when it switches off,
  and its tint spreads in behind the press ripple (`QuickToggleTile`); chips pop (`ChipRow`,
  `ToggleChip`, `PresetChips`); a switch's thumb stretches and springs (`Toggle`); a
  `ChipButton` leans toward the pointer and dips under a press; stepper buttons squash.
- **Hover life.** Cards and tiles carry the light under the pointer (`PointerGlow`); a rail icon
  leans toward its page.
- **Live heroes.** A page's top card shows the real thing, live: the palette, the warmth
  strip, the cursor sheet, the dock strip, the screen-time week, a widget, the launcher's own
  field typing its hints.
- **Typing hints.** An empty search field types its own hints (`TypedPlaceholder`, the
  launcher's): settings search, Wallpaper, Keybinds. Give an `InputField` hints only when
  the field has something to teach, and keep them short in a narrow box.

Everything runs through `Motion`, so "Animations: off" is a plain swap.

### 1.5 Material 3 Expressive (2026-11-09, stage 1: the shared controls)

User picks: foundation first, then the neglected pages; tonal M3E cards and heroes; an expressive window.
Stage 1 changed the shared pieces, so every page inherits it:

- **Cards.** `Section.cornerRadius` defaults to `Tokens.radiusXl` (24). The heading chip is TONAL: the palette's
  `primaryContainer` with `fgOnPrimaryContainer` for the glyph, no outline (a card with another accent mixes its own
  container the same way). `Section.tonalAccent` says which.
- **Page header.** `SettingsPage` passes `morph` / `chipSize` / `titleVariant: "headline"` to `PanelHeader`: a badge that is a
  `MorphShape` on `primaryContainer`. `headerShape` picks the shape; left empty it is chosen by the page's title, so each
  page wears a different one and the same page always the same. The three pages with their own `PanelHeader` (Updates,
  Wallpaper, Keybinds) set the same four properties by hand.
- **Toggle tiles.** `QuickToggleTile` (roomy) badge is a `MorphShape`: a disc when off, `shape` when on, on the spring that
  overshoots (`ShapeTile`'s move). `shape` defaults to one of eight by the tile's label. The old pop of a rounded square is gone.
- **Switch.** `Toggle` is Material 3's: 52×32 capsule, thumb 20 off / 24 on / 28 pressed (equal air all round), a state-layer
  halo behind the thumb (`Tokens.stateHover` / `statePress`). The smear on a state change stays; pressing does not smear.
- **Slider.** `ValueSlider.expressive` (opt-in; `Fader` and `SliderRow` set it, the bar's and the mixer's stay hairline): a 16px
  active track that stops 6px short of a thin vertical handle (4px, 2px pressed), the rest of the track beginning past it.
- **Not yet (stages 2+):** `ChipRow` / `SegmentSwitch` as connected button groups, the rail's indicator, and the page
  rethinks (system plumbing, integrations, the big data pages).
- **Unverified live:** all of it was checked only in the headless sandbox (`bash scripts/smoke-headless.sh --shots DIR`), whose
  palette is monochrome — so the tonal container reads as grey there; the real wallpaper palette is the actual test, and
  so are the springs and the press feel.

### 1.1 The corner language — cards soft, controls capsules

| Level | Radius | Examples |
|---|---|---|
| Hero | `radiusXl` (24) | the one big card at the top of a page |
| Cards | `radiusCard` (16, Hyprland's window rounding) | `Section`, `QuickToggleTile`, every panel and popup |
| Controls | capsule (`height / 2`) | `PanelButton { capsule: true }`, `ChipRow`/`ToggleChip`/`PresetChips` chips, `ChipButton`/`ChipTray`, `SegmentSwitch`, text fields, the rail's pill and rows |
| Rows | `radiusSm` (8) | list rows inside a card, stepper buttons |
| Details | `radiusXs` (4) | a checkbox, a tick chip |

The same table holds for the panels. Capsule radii are written `height / 2` (as the panels do),
so they ignore the "square" bar-shape mode on purpose. A chip that is a filled disc is the
chosen one: unselected chips are a faint wash (`fg` at 0.06, 0.12 on hover) with no outline, so
a row of options spends its weight on the one that is picked.

### 1.4 One filled accent per region

A section's icon chip is the one filled accent in its card; the rows below stay
untinted. A filled accent says "this is the value" (a selected chip, a checked
switch) — spending it on decoration makes the real ones stop registering.

---

## 2. The components

Reach for these before writing your own:

| Component | For |
|---|---|
| `SettingsPage` | the whole page shell — header, rule, banner, scrolling grid of columns |
| `SectionColumn` | one column of a page; the page hand-groups them |
| `Section` | a titled card: glyph chip, title, subtitle, `actions`, body |
| `SettingRow` | label + detail + one control (`wrapDetail` for a real sentence) |
| `ChipRow` | one value out of a handful, as pills |
| `ToggleChip` | one yes/no in a SET (which modules are on the sidebar, which blocks the lock screen shows) — filled when on; `hint` is its tip |
| `PresetChips` | saved looks: tap to load, the worn one filled, rename/remove slide out on hover, "+ Save current" |
| `HelpTip` | puts a control's explanation in the card's tip (§6a). Built into the controls as `help` |
| `PointerGlow` | the light under the pointer on a card (Section and roomy tiles have it) |
| `Disclosure` | a fold — what is set once and left. Lazy: built when opened |
| `Fader` | a continuous value — a percentage, a multiplier, fps |
| `SliderRow` | a value you must land on exactly — pixels, minutes, Kelvin. Fader's shape plus an outlined − + |
| `Toggle` | a switch |
| `InputField` | any single-line field. `seed` to prefill, `edited`/`committed`/`accepted` |
| `PanelButton` | an action inside a card. Settings pages set `capsule: true`; `variant: "primary"` at most once per card |
| `ChipTray` + `ChipButton` | a page header's actions (Arrange, Reset, Refresh…): the panels' tray of round chips, `on` for the filled one, `label` to make it a pill |
| `TabStrip` (= `SegmentSwitch`) | the view switch, and a two-to-four-way choice inside a card |
| `ViewEnter` | a card arriving; `Section` and `QuickToggleTile` already use it |
| `ShapeBox` | the icon chip (rounded square, or `Config.iconShape`) |
| `CookieButton` | the one primary, outward-reaching action on a page |
| `WaveSlider` | a level that carries its own live signal (audio) |
| `RadialGauge` | one proportion, at size — a charge, a disk |
| `UndoBar` | a reversible delete's way back (see §6) |
| `Divider`, `Meter`, `BusyDot`, `Scrollbar`, `Sparkline` | as named |

Never hand-roll a text field: four drifted copies existed before `InputField`, and
`Keyboard`/`Storage`/`Widgets` each carried another until this overhaul.

---

## 3. The page shell

```qml
Item {
    id: root
    // services, drafts, derived properties, page-local components

    SettingsPage {
        anchors.fill: parent
        columns:   2                    // == the number of SectionColumns declared
        glyph:     "󰸌"
        title:     "Colour"             // fixed word
        titleTail: "theme"              // the accented half
        accent:    Colors.primary
        subtitle:  <one line, priority-ordered: blocker > status > count>

        actions: Toggle { … }           // or [a, b] — header-right controls
        banner:  SomeStrip {}           // fixed, above the scroll

        SectionColumn { Section { … } Section { … } }
        SectionColumn { Section { … } }
    }
}
```

The root stays an `Item` wrapping `SettingsPage`, never rooting at it: the card
loads pages by file and anchors what it gets, and a page that IS the page shell has
nowhere to put its own properties and inline components.

Header actions are a `ChipTray` of `ChipButton`s (`actions: ChipTray { ChipButton { … } }`), not
a bare `PanelButton`: a filled disc (`on: true`) is the header's one primary action, a master
switch stays a `Toggle`. A page with its own `PanelHeader` (Widgets, Keybinds, Storage, Updates,
Wallpaper) puts the same tray in it, and draws no rule under it — the panels' headers have none.

### 3b. Bento — the default for a page of settings

`SettingsPage { bento: true }` swaps the hand-grouped columns for a mosaic. Children
are TILES, each declaring `span: 1..3`; the grid picks 1–3 columns from the width.

```qml
SettingsPage {
    bento: true
    …header…

    Section { span: 3; title: "Your palette"; … }        // the subject, full width

    QuickToggleTile {                                     // a boolean is a TILE
        roomy: true
        symbol: "wallpaper"
        label:  "Theme from wallpaper"
        active: Config.wallTheming
        subLabel: Config.wallTheming ? "Every new wallpaper repaints the shell"
                                     : "The palette stays exactly as it is"
        onToggled: Config.wallTheming = !Config.wallTheming
    }

    Section { span: 2; title: "Accent"; … }               // a group that needs room
}
```

Rules that make it read as one page rather than a pile:

- **The grid fills its rows — you do not tune `span` to avoid holes.** The body is a
  `BentoGrid` (`components/BentoGrid`, packing in `services/bentopack.js`, tested by
  `bun scripts/test-bentopack.js`). A plain `GridLayout` wraps an item that doesn't fit
  the rest of a row and leaves that space blank, and centres a short item beside a tall
  one — that was the "empty spaces" on every page but Theme, which tiled by luck. Now
  `span` (1–3) is only what an item WANTS; the grid widens each row's items until the
  row is flush (two tiles on a three-column page become halves, a lone last tile takes
  the row) and stretches them to the row's height, so neighbours share edges. Under it
  the grid has six sub-columns with an anchor row (zero-height cells), because a grid
  sizes a column from the single-cell items in it and otherwise 3|3 over 2|2|2 comes out
  uneven. Rules that follow: an item in a bento body must be `Section`, `QuickToggleTile`
  or a type that binds `Layout.columnSpan` to `parent.spanFor(this)`; hide with
  `visible` (the grid re-packs) or dim with `available: false`; and group cards of
  similar HEIGHT in the same row, because the shorter card is stretched, not shrunk.
- **A boolean is a tile you tap, never a row with a switch at the far edge.** The
  fill and the chip carry the state, plus one word (On/Off) — all legible across the
  whole grid, which a switch position is not. `QuickToggleTile { roomy: true }`.
- **`subLabel` says what the state MEANS**, and changes with it. "Bar, panels and
  overview only" beats "Recolour every app too" with a switch you have to read.
- **A dependent setting sets `available: false`** rather than vanishing: it dims,
  stays where it was, and still says what it would do.
- **One thing the page is ABOUT gets `span: 3`** — the palette, the warmth strip, the
  charge ring. If nothing on the page deserves that, the page is a list: don't use
  bento.
- **Two to four mutually exclusive values are a `TabStrip`**, not chips: the
  selection slides between segments.
- **Every `symbol`/`icon` name needs an `icons.js` entry** or machines without the
  Material Symbols font get a "?" — that file is generated, so pick a mapped name.
- **New control type carrying a label? Add it to `scripts/build-settings-index.py`.**
  The first bento conversion silently dropped eight settings out of search because
  the builder only knew `SettingRow`.

**A page that is a picker, a list or a dashboard does not use `SettingsPage`** —
Widgets, Wallpaper, Keybinds, Updates and Storage own their layout so a list can
fill the height. (Bar used to be on that list and no longer is: split into three
views, each one fits the shell.) They still open with the same `PanelHeader` (no rule under it) so
the top of every page matches.

---

## 4. The rail, pages and views

`services/SettingsIndex.qml` is the catalogue: seven rail PAGES, each with one or
more VIEWS. A view is one file in `pages/`.

    Appearance      Theme · Type & shape · Night light · Cursor · Sound effects
    Wallpaper       (one view, with its own Gallery | Appearance | Engine strip — drawn in the
                    same place as every other page's strip)
    Bar & sidebar   Modules · Style · Behaviour · Panels   (2026-11-08: one page for both
                    surfaces; Dock and Stats are modules, their settings in the inspector)
    Desktop         Widgets (Desktop · Style · Content modes, a header switch) · Lock screen · Keybinds · Tuning
    Devices         Sound · Network · Bluetooth · Keyboard · Battery
    Apps & tools    Launcher · Clips · Screen time · Lyrics · Discord · Presence
    System          Updates · Setup (with the shell presets) · Storage · Language · About

Regrouped 2026-10-26: no page has more than six views (Devices had eight), and each view sits
under the page that describes it — Sound effects is how the shell FEELS (Appearance), Launcher,
Clips and Screen time are things it DOES (Apps & tools), Language is the machine's (System).
Shell presets stopped being a page of their own and are Setup's last card ("set up this
machine" and "set up the next one" are one trip); `ShellPresetPage.qml` resolves to Setup
through `SettingsIndex.aliases`, so a saved preset naming it still lands.

Network replaced Wi-Fi + Traffic: the card at the top is the CONNECTION whichever medium
carries it, and the Wi-Fi card exists only where there is a radio. `NetworkTrafficPage.qml` and
`WidgetStylePage.qml` resolve through `SettingsIndex.aliases` (to Network and Widgets).

**Every page keeps its tab strip** (the user's call, 2026-10-07). Sidebar & dock was a
composed scroll of groups for a while (`SidebarDockPage`, `SettingsGroup`, `GroupFold`);
it was the one page that scrolled where the rest tabbed, and is five views again. A
remembered `SidebarDockPage.qml` resolves through `SettingsIndex.aliases`. The `members`
mechanism (`hostOf`, `UiState.settingsGroup`, `SettingsPage.scrollToItem`) is still there
for a view that holds another's rows; nothing uses it today.

- `SettingsCard` draws the rail, and a `TabStrip` above the page when a page has
  more than one view. **A page with rail views never draws its own strip** — two
  strips stacked reads as tabs inside tabs. A single-view page may own one: Wallpaper
  (Gallery | Appearance | Engine) does. (Its Gallery is the original 3×3 pager: a
  redesign was tried and declined, 2026-10-07.)
- **A sub-mode of one view is a header control**, not a strip: Storage's
  Disks | Packages is a `ChipTray` of two `ChipButton`s in the page header; Widgets' gallery
  is a header chip that takes over the body.
- File names are unique across the catalogue, so `Config.settingsPage` and
  `UiState.openSettingsTo(file)` still name a file and the page is derived.
- A view gated on hardware sets `available: false`; a page whose views are all
  hidden disappears from the rail.
- Search lives in the rail and covers every row on every page — rebuild the index
  after adding or renaming anything: `python3 scripts/build-settings-index.py`. It
  reads literal `title`/`subtitle`/`label`/`detail`/`help` strings, ONE property per
  line (`symbol: "x"; label: "y"` on one line drops the label).

## 5. Selection semantics

- **The rail's current page** is a solid accent capsule, and its icon fills in. What stops it
  reading as a button is SIZE: a rail item is a full-width row in the navigation slab, a chip is
  a hug-width capsule inside a card.
- **A chosen value** (ChipRow, TabStrip segment, a selected device row) is a filled
  accent wash.
- **An action** is a `PanelButton`; `primary` means "the one thing this card is
  for", so at most one per card.

---

## 6. Fitting the window

**A settings page should not scroll.** The budget is ~920 × 650. Two columns of
~450 each, and about 650px of height per column.

- `SettingsPage.minColumnWidth` is **360** and the gap is `spacingLg`. It was 520
  with a 24px gap, which needed 1064px — so every `columns: 2` page silently
  rendered as one long column at the size the window actually opens at. If you
  change these, re-derive against §0.
- **Group by height, not by count** (`SectionColumn` documents the rule): a column
  that ends 300px above its neighbour reads as unfinished.
- **Windowed lists.** A `ListView`/`GridView` inside a page gets an explicit
  `Layout.preferredHeight` (rows × row height) — they report no implicit height, so
  an unbounded one either collapses to nothing or makes the page the scroll.
- **Compact rows where a card is mostly switches**: a column of label + switch with
  the whole row as the hit target (LockPage's "What it shows"), or a one-line
  mark + name + a word of status, the fix behind a tap (SetupPage's `Check`), instead of nine full `SettingRow`s.
  A switch only needs a sentence of explanation when nothing on the page shows what
  it does — see §6c.
- **Labels beside fields, not above** (`FieldRow` in Discord) — a label over
  every input doubles a card's height.
- When a view genuinely holds two jobs, split it into two views rather than
  scrolling: Keybinds/Tuning, Discord/Presence, and Bar into
  Modules/Style/Panels.
- **A shell-wide setting belongs on a shell-wide page.** `motionEnabled` /
  `motionScale` run every duration in the app through `Motion._d()`, and they sat on
  the Bar page because that is where they were written first. They are in
  Appearance › Type & shape now. Ask what a setting GOVERNS, not where it was born.

---

## 6a. Text, and which control

**A control carries a name and, at most, one short state line** (≈8 words) that says
what the current value MEANS ("Every new wallpaper repaints the shell"). The sentence
that explains why it exists is its `help` — a tip the card draws when the pointer rests
on the control, with a small ⓘ beside the label while hovered (`Section`,
`QuickToggleTile`, `SettingRow`, `Fader`, `SliderRow`, `FontPicker` take `help`;
`ToggleChip`'s `hint` is the same thing). Card subtitles are states ("3 of 10", "Off",
"From DHCP"), never descriptions. A warning that matters right now stays visible
(the lock screen's "log out discards unsaved work", the mic test's "headphones only").

Which control:

- **A boolean worth a sentence** → `QuickToggleTile { roomy: true }`.
- **A set of yes/no's** (membership: what is on the sidebar, what the lock screen
  shows, what stands on the dock, what a clip captures) → `ToggleChip`s in a `Flow`.
- **Several booleans of one kind in one card** → `SettingRow` + `Toggle` rows (Dock's
  Behaviour, Stats' Rings). Four tiles would be a screen of their own.
- **A card's master switch** → the `Toggle` in the Section's `actions` (Motion, Ask,
  Alerts, the visualiser), not a row inside it.
- **Two to four exclusive values** → `TabStrip` (edge, size, °C/°F, scope). More, or
  values that wrap → `ChipRow`. **One-of-N in a list** (audio devices, DNS) → rows with a
  radio mark (`check_circle` / `radio_button_unchecked`), never checkbox glyphs.
- **A number** → `Fader` (continuous) or `SliderRow` (exact). Both draw one shape;
  HyprTuningPage's local slider (commits on release) draws it too.
- **Saved looks** → `PresetChips`. **A text field** → `InputField`, including passwords
  (`secret: true`) — Updates and Storage each had a hand-built one.
- **One-line facts in a narrow card** → one column; two only when wide
  (`columns: width >= 640 ? 2 : 1`).

Pairing at the reference size: two cards of similar HEIGHT in a row (the grid stretches
the shorter). A `span: 2` card fills the whole row at two columns, leaving the card before
it alone and stretched — prefer `span: 1` pairs.

## 6b. The app-wide behaviours

These live in `SettingsCard`, not in pages — a page that re-implements one has
already drifted:

- **Keyboard:** `Ctrl+F` focuses search (unfolding the rail if needed); `↑↓` walk
  results while searching and the rail otherwise; `←→` walk the current page's views;
  `Enter` opens the selection; `Esc` clears the search, then closes.
- **Pinned views** (`Config.settingsPinned`) sit above the rail's page list. Pins are
  FILES, so they survive the catalogue renumbering when hardware appears.
- **Undo, not confirm**, for anything reversible: capture what you need to restore
  BEFORE deleting, then `undoBar.show("Deleted X", function () { …restore… })`. A
  confirm dialog taxes every correct action to prevent a rare wrong one. If a thing
  genuinely cannot be restored (forgetting a Bluetooth pairing drops a key), use a
  hold-to-confirm instead — never an undo that lies.
- **Live headers:** a page header states a reading, not a description. Sound says the
  volume, Storage says the free space, Keyboard says the layouts and the repeat rate.

---

## 6c. Previews — the real component, or nothing

A setting whose effect is somewhere else (the desktop, the bar, the overview behind
this window) can be worth showing. The bar is strict about HOW:

- **A preview is the real component, rendered small and inert.** Never a drawing of
  one. `modules/desktop/widgets/WidgetPreview` scales the same `WidgetFrame` and the
  same widget file with `active: false`; `modules/settings/BarPreview` mounts the
  bar's own `BarRegion` / `BarGroupRow` off `Config.layout` inside one
  `enabled: false`. Both read the same `Config` the real thing reads, so neither can
  disagree with it.
- **The real function, when the thing itself cannot be here.** Lyrics › Motion moves
  a line of lyric through `LyricMotion.wordMotion()` — the function `LyricGlyphs`
  calls per syllable, at the user's own intensity.
- **No drawn mock-ups.** A lock screen made of rectangles and a diagram of a panel
  sliding to one side were both built and both removed. They were accurate and they
  still read as clip art, and each was a second implementation that starts lying at
  the first change. **If the real component cannot be mounted, say it in words in the
  row** — LockPage's switches carry their position ("bottom centre", "right edge")
  taken from where `LockScreen.qml` anchors that block, which is what the picture was
  there to say.
- **Previews cost nothing when idle.** No preview loops an animation on its own: the
  lyric line plays on hover and once per slider move, the battery ring breathes only
  while charging.
- **`PreviewStage`** is the recessed frame for one: checkered when the subject is
  translucent, `checkered: false` when it isn't.
- **Sizing bite:** `PreviewStage` hugs its content (`childrenRect`), so a child that
  FILLS it (a grid `Canvas`) makes that height depend on itself. Give the stage an
  explicit `Layout.preferredHeight` measured from the content item
  (`tiles.implicitHeight + padding * 2`).

---

## 7. Things that will bite

- **`Layout.fillHeight` defaults to TRUE** for a layout nested in a layout. Every
  `RowLayout`/`ColumnLayout`/`PanelHeader` directly inside a page's top column needs
  `Layout.fillHeight: false`, or it splits the surplus with the body.
  `check-qml-fillheight.py` catches most of it.
- **`Scrollbar` reparents itself to `flickable.parent`** and anchors across it, so
  that parent must be a plain `Item`, never a Layout (a `Section` body is one).
- **`InputField.text` is a readonly alias.** Prefill with `seed` (applied only while
  unfocused); binding `text:` breaks on the first keystroke.
- **`Quickshell.env()` returns a QVariant** — an unset variable is `undefined`, not
  `""`. Use `(Quickshell.env("HOME") || "")`.
- **Never redeclare a property the base already has** — that's
  `Property value set multiple times`, a hard load failure that cascades.
  `check-qml-duplicates.py` catches it.
- **Every new `.qml` needs its `qmldir` line**, or it's "not a type" at runtime with
  no static warning.
- **Verify a new Nerd Font glyph** against the installed family before shipping it:
  `fc-list ":family=CodeNewRoman Nerd Font:charset=f0fb0"`. A missing one renders as
  an empty box. `MaterialIcon` names need an `icons.js` entry too, or machines
  without the Material Symbols font get a "?" — `icons.js` is generated, so pick a
  name it already carries.

---

- **Pages are not hot-reloaded.** A page is loaded by path when you open it, so the
  reloader (which watches imported files) never sees an edit to it, and the engine keeps
  serving the compiled old one. `qs ipc -p ~/.config/quicktest call shell reload` reloads
  in-process (the settings window survives). The same goes for a new `qmldir` line: it is
  read when the engine starts.
- **`Layout.maximumWidth: implicitWidth` elides.** The layout floors widths to whole
  pixels, so a 49.4px label gets 49 and elides. `Math.ceil(implicitWidth)`.
- **Inline components can't see this file's ids** under `ComponentBehavior: Bound`: pass
  geometry in from the use site (`PageSlot`'s anchors).
- **`left`/`right`/`top`/`bottom` are FINAL on Item** (anchor lines) — name an animated
  edge `edgeL`, `topY`… (`check-qml-final.py`).

## 8. Before reporting done

1. `python3 scripts/check-qml-aliases.py`, `check-qml-duplicates.py`, `check-qml-final.py`,
   `check-qml-palette.py`, `check-qml-fillheight.py <files>`, and `check-glyphs.py` — a
   Nerd glyph that is neither mapped in icons.js nor in the bundled glyph font draws
   NOTHING, silently (four card headings shipped blank that way).
2. The parse idiom on each changed file (syntax only — say so):
   `sed -E 's/\?\.(\[|\()/\1/g; s/\?\./\./g' f.qml > /tmp/c.qml && qmlformat /tmp/c.qml | wc -c`
3. `python3 scripts/build-settings-index.py` and `bun scripts/test-settingssearch.js`.
4. Propose the transient load (CLAUDE.md) — never run it unasked.
5. Say which parts only a reload can judge: anything visual, anything that writes to
   disk, anything that needs hardware.

## 9. Patterns from the per-page pass (2026-10-26)

Inline components, not new files (a new file needs a qmldir line, read only at engine start):

- **Mixer** (SoundEffectsPage): vertical pill faders — drag/scroll/tap, written on release —
  with the selected channel's detail beneath. One control model for seven volumes.
- **Space map** (StoragePage, `services/treemap.js`, `bun scripts/test-treemap.js`): a
  squarified treemap; tile area is the folder's share, hover is the path. Use it when
  items are parts of a whole and the biggest should be obvious.
- **Load bars + thread cells** (AboutPage): a figure and one `Meter` per resource; threads as
  cells whose fill is their load. No rings, no history traces.
- **Check** (SetupPage): a status row that says a word or nothing; expandable only while
  outstanding, with a copy chip for the fix.
- **Hero that follows state** (NetworkPage): the top card names the real connection (Ethernet,
  Wi-Fi or none) instead of presuming Wi-Fi.
- **Device tiles** (BluetoothPage): tap = connect/disconnect, hover reveals trust/forget.
- **Stacked bars with names resolved** (ScreenTimeView): `services/screentime.js` turns
  `steam_app_<id>` into the game's title from Steam's appmanifests.
- Launcher behaviour is a set of `Config.launcher*` switches (actions, settings, calculator,
  packages, AUR, learning, rows); the services read them, the page only flips them.
