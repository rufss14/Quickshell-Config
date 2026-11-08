# Translations

`services/Translation` + `translations/*.json` + `scripts/translations.py`. ii-style: the English text
is the key.

    text: Translation.tr("Reload failed")
    text: Translation.tr("Moved %1 keys").arg(n)     // a sentence with a number takes a placeholder
    label: Translation.tr(modelData.label)           // data: mark it N_("…") where it is written (hud.js)

- **Fallback is English, always.** No file, no entry or an empty value returns the text unchanged. An
  English locale reads no file at all.
- **Which file:** `Config.uiLanguage` ("auto" = `Qt.locale().name`). Exact code, else any file in the same
  language ("pt_PT" gets pt_BR's), else English. Switching applies live — `tr()` reads `table`, which is
  reassigned whole, so every binding re-evaluates. The file is watched, so a translator's save shows at once.
  Picker: Settings › Devices › Language › Shell language (not the system locale below it).
- **Tooling:** `python3 scripts/translations.py extract` (rewrites the generated reference
  `translations/en_US.json`), `check`, `status` (coverage per language), `sync`, `new CODE`.
  `scripts/test-translations.py` fails when `en_US.json` is stale or a call isn't one literal — run `extract`
  after adding a string. Comments are ignored. One literal only: `tr("a " + b)` can't be translated.
- **2026-11-08:** every single-literal `text/label/title/subtitle/detail/help/placeholder/tip/…: "Text"` line in
  modules/ and components/ is wrapped (1,133 strings, 122 files; a scripted pass — lock and greeter screens left
  alone), so the catalogue holds ~1,300 strings. Still English-only: strings built by concatenation or a ternary,
  JS data tables, the lock screen and greeter.
- **Coverage before that:** only what was wrapped — everything written in the 2026-10-10 round (polkit prompt, HUD,
  snip tool, song recognition, to-do, reload card, secrets, session warnings, rival detection, the new dock /
  shape / reveal / language settings). The other ~370 files and the settings navigation (built from
  `SettingsIndex`, which the search is coupled to) are still English. No translations ship: that is
  contributors' work, and machine-written ones would not be reviewable by the maintainer.
- **The settings search index** is built from the English text: `build-settings-index.py` reads through
  `Translation.tr("…")` so wrapped labels stay searchable, but typing a translated word finds nothing.
- Known limit: a two-word panel title (`title` + accent `titleTail`) is two strings, so a language that
  reorders them can't.
