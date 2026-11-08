# Karaoke

Sing along and the lyrics light up — and it is an osu!-style GAME with ranks, a combo, a results screen and saved
scores. Built 2026-10-17 at the user's ask ("compare the lyrics to my voice
and light up if it matches"); moved from a sidebar cell to the **media panel** the same day, detection
reworked. **Built and statically checked; never loaded, never run against a real microphone or a real
speech model.** The project rules in CLAUDE.md still apply.

## Where it is

- **The header chip** of the media panel (`MediaPanel`, a `mic` ChipButton, only on a song with lyrics):
  click starts / stops listening. Never disabled — a click that can't start it says why (headphones,
  pw-record) for a few seconds in the header subtitle (`Karaoke.notice`).
- **The header subtitle** (where SongRec already says "Listening…"): `Karaoke.headline` — "Listening",
  "Singing  ·  82%  ×3" (the song's score, and the streak from two), and for a few seconds after a click that
  couldn't start it, why (headphones, pw-record). A strip on the lyrics card did this first and was moved
  at the user's ask.
- **The underlines** (`modules/overview/KaraokeMarks`, inside `OverviewLyrics`'s lead block, so on every
  surface that draws the card): a thin line wipes in, left to right, under each word you have sung — on
  EVERY line you sang, not only the current one. They are read from `Karaoke.sung` (line index → per-word
  flags, kept for the song), so a line keeps its marks after the song moves on and fades with the line; a
  seek drops the lines from where it landed, so a line sung again starts clean. (They were first read off
  the current line alone and vanished the instant it changed.) An OVERLAY on the line's own text layout (`positionToRectangle`), not a change to
  `LyricGlyphs`. Words only — with timing alone there is no word to mark. A word that wraps onto the
  next row is left unmarked.
- **The HUD** (`modules/panels/KaraokeHud`, over the lyrics card in `PanelLyrics`, no input): the COMBO top left —
  per WORD: every word you sing nudges it, every 10 (harder at 25, 50, 100) it pulses with a ring, and a break
  flashes it in the danger colour, shakes it and lets it fall — with GET READY (a bar draining to the first line)
  in the same corner during the grace period; and top right a pill: the rank you are on track for, the accuracy
  (digits roll; the badge pops on a change of tier), and — for a moment after each line — its JUDGMENT, which
  unfolds out of the pill's left edge and folds back. (It used to float across the middle of the card, on the
  words being sung.) An `UNRANKED` tag sits under the pill for a run that cannot rank. Nothing draws over the
  lyrics. The listening status is the panel's subtitle, not here.
- **The results screen** (`KaraokeResults`, a Loader over the whole media panel, built only while the panel is on
  screen so the entrance plays when it can be seen): the cover blurred behind a card; a headline for the rank
  (FLAWLESS … TRY AGAIN); the rank slams in (large, tilted, overshooting), a ring leaves it, S and SS throw
  confetti, SS keeps breathing, F lands and shakes; accuracy (with the gap to your previous best, up in the
  success colour or down in danger, and a "S → SS" chip on a rank-up), score, max combo, WORDS hit (with a
  recogniser) and lines all count up; a LINE BY LINE graph — a column per judged line, its height its points, its
  colour its judgment — sweeps in left to right; the four judgments fill their bars. Buttons: Close, **Play again**,
  **Next song**, Scores. One timeline (`cardIn → rankIn → ringT/countT/barsIn/graphIn/burst/shakeT`), so the rank
  always lands before the figures count. The confetti's scatter is fixed arithmetic on the particle's index.
- **Joined mid-song** (`KaraokeJoin`, over the panel while `Karaoke.joinNotice` or a countdown runs): "This run
  won't be ranked", with **Sing anyway** and **Restart · 3s countdown**, which pauses the song at 0:00, counts
  3-2-1 (a numeral per second with a ring running down) and plays — a fresh run that can rank. Disabled, with a
  note, for a player that can't seek.
- **The Scores tab** (`KaraokeScoresView`, a third segment of the media panel, behind a Loader so the list slides
  in afresh each visit): every finished song with its cover, best rank / accuracy / score, plays; a row opens to
  its judgment counts, its last runs as a bar chart in each run's rank colour, and a delete that wants two clicks.
- **Settings tab** of the media panel: Sing along, Match the words, I'm on headphones.
- There is **no sidebar module** any more (`SideKaraoke`, its catalogue row and its hover-card kind were
  removed at the user's ask). `Karaoke` is a lazy service: `qs ipc … call karaoke on|off|toggle|reset|status`
  exists once the media panel or a lyrics card has been built, like Lens.
- It is never persisted and never started by anything but a click or IPC: the microphone is not
  something a saved preference should open.

## What "a match" means

The song has no pitch track to compare a voice with, so there are exactly two signals:

- **Timing** — you are voicing while a lyric line is on (a beat early to a beat late).
- **Words** — a speech recogniser's output, set against the lines around now. Optional, rough, the
  better evidence. With words a line's points are its WORD score (curved, below) times 0.75–1 by timing; without, timing alone.

`lit` (0..1) is how lit you are right now; `glow` is the same, smoothed (below). The session score is the
mean of the lines that sang something and were on long enough to judge (>= 600 ms — a line you seeked into
is not a line you missed); the streak counts consecutive lines scored >= 0.5.

## The game (2026-10-17)

Every line you sing is JUDGED by its points (0..1): **PERFECT** >= 0.90 (300), **GREAT** >= 0.70 (200), **GOOD**
>= 0.50 (100), **MISS** below (0). **Accuracy** is the mean of the judged lines' points, as a percent. The **rank**
is read off it, as it is DISPLAYED (to a tenth: 89.96 shows 90.0 and is an S):

    SS+  exactly 100%    SS  95–99.9    S  90–94.9    A  80–89.9    B  70–79.9    C  60–69.9    F  below 60

**SS+ is flawless or nothing.** The accuracy is shown to a tenth, and 99.96 would round UP to a displayed 100.0 —
an SS+ for a run that missed. So the displayed accuracy is capped at 99.9 unless the run was exactly 100
(`displayAccuracy`), and the rank is read off the displayed number. SS+ gets a brighter tone than SS, two halos
(the second half a beat behind), the most confetti (56) and the headline PERFECTION.

A line's points = word score x (0.75 + 0.25 x timing), where the word score is the share of the line's words
heard over the share that is full marks (70%), to the power 1.5 (`WORD_CURVE`): 7 of 10 words is 1.0, 5 of 10 is 0.6
(a Good), 3 of 10 a Miss. **A line with no word landed is 0** — until 2026-10-18 it was 0.25 for being voiced in time,
and replayed over 199 cached lyrics a whole song of OTHER words came out ~32% accuracy, mumbling ~30%, and half the
lines wrong ~65% (a C); now 6%, 4% and 52% (an F). The matcher itself is not the leak: wrong lyrics light ~7% of a
line's words by chance, "la na oh" ~4%. Real singing costs a little too: with 75% of the words recognised the same
songs went 96.5% -> 94.0%. Timing alone (Match the words off, or no model) is unchanged: it hears whether you sang, not
what, so humming in time is full marks there. A silent line is judged, and is a miss —
that is what gives the accuracy meaning. Only lines that sing something and were on for >= 600 ms are judged.

**Mods** (osu!-style; `KJ.MODS`, switched in Media › Settings › Karaoke › Mods, `Config.karaokeModHidden` /
`…HardRock` / `…TimeHell`). Each makes a run harder in one way and its SCORE worth more by a multiplier; they change
how a run is JUDGED (so the accuracy and rank are earned against the harder rule), and the multiplier is on the
score only — never on the accuracy. They stack by multiplication.

| mod | what it does | x |
|---|---|---|
| **HD** Hidden Lyrics | PARTIAL hide: only the line being sung is shown; the rest fade out (the layout stays put). Judging unchanged | 1.06 |
| **HD+** Hidden Lyrics, all | hides EVERYTHING, the current line too — you sing from memory (`HDP`; replaces HD, never both; `Config.karaokeModHidden` is 0 / 1 / 2) | 1.25 |
| **HR** Hard Rock | stricter WORDING: no "close enough to the ear" (spelling must be 85% right: seven letters or more for one wrong letter, nothing for a short word), and 90% of a line's words, not 70%, is full marks. With no recogniser there is no wording to be strict about, so it earns nothing (`effectiveMods`) | 1.12 |
| **TH** Time-Hell | strict TIMING: the window a voice counts in shrinks (a beat early / a beat late → 0.05 s / 0.1 s), a line opens to its words 0.3 s ahead (was 0.8), a finished line settles after 0.5 s (was 1.2), and 65% of the window voiced, not 45%, is full marks | 1.20 |

The mods also sit in a pill of their own in the Media panel's header, to the LEFT of the pill with the mic button and
shown only while Sing along is on (`groupShown: Karaoke.active && root.showLyrics`): HD (a click cycles HD → HD+ → off),
HR, TH, in bold labels (`ChipButton.labelWeight`). A chip wears the warning colour while `Karaoke.modsPending`. With
Sing along off they are still set in Settings.

Mods are read when a run BEGINS and fixed for it (`_takeMods`: on activation, a new song, a restart, a replay);
changing one in Settings mid-song says it applies from the next run. The numbers they change are one `rules(list)`
object threaded as an optional trailing parameter through `inWindow` / `lineOpen` / `timing` / `wordScore` /
`points` / `lineResult` / `sameWord` / `matcherHear`, defaulting to the normal rules — so nothing changes unless a
mod is on. The HUD pill shows the active mods; the results screen shows them and the multiplier they earned; the
scores table stores them with each run (sanitised: only the known mods, once each, in order) and the Scores tab
shows the best run's. A song's best is still the higher accuracy, then the higher score — so a modded run (harder,
and worth more) competes with a plain one on that rule; they are not kept apart.

**The combo is per WORD** (it was per line, which made a long song's counter crawl and hid "I dropped that
word"). It is DERIVED: the run of consecutive lit words ending at the word just sung, carried across line
boundaries (`KJ.comboRun`), so a skipped word cuts it by itself; a line that ends with its last words unsung and
nothing later sung breaks it (`comboSurvives`). With no recogniser the words are not heard one by one, so a line
that is not a miss adds its words to the combo and a miss breaks it. A line's score is its value times a
multiplier from the word combo at that moment, x1 to x3 by 100 words.

**A grace period for a song that starts too fast.** Every seek — which includes the first position of a run and of
a song — starts `GRACE_S` (6 s) of SONG time (a pause does not spend it); a line that starts inside it is a
WARM-UP: if it comes out a miss it is simply not counted (no accuracy cost, nothing broken); one you sing well
counts in full. A GET READY bar drains to the first line meanwhile.

**A grace period after a line switches** (2026-10-18). A line just left is kept for its late words, then judged
(`_pendings`, a queue, oldest first). The wait is `KJ.settleAfter`: `graceMs` (1.2 s; Time-Hell 0.5 s) for a line of
2.5 s or more, rising to twice that for a line of 1 s or less, because in a fast song the recogniser's lag and the
singer's trailing are the same size as the line. Waits never end out of order, so lines are judged in order. It was
one pending line with a fixed 1.2 s, and a second line ending inside it REPLACED the first without judging it, so a
fast song silently dropped lines (neither a hit nor a miss). A late word is also taken from behind: when a heard word
fits nothing ahead of the cursor, `_find` tries the unlit words of the pending lines, nearest first, and lights one
without moving the cursor (a word that fits ahead is never taken from behind). Not covered: the LAST line, which has no
next line to switch to — it keeps the 1.5 s `songDone` wait. Never run on a real fast song.

**Lines that are not counted** (2026-10-18), two kinds (`karaoke.js` "Lines that are not to be counted"):

- **Left out by the user.** Right-click a lyric on any lyrics card (`OverviewLyrics.skippable`, off on the lock screen)
  and it is dimmed and not part of the score, for that song; right-click again to put it back, or Settings › "Lines left
  out" › Put all back. Kept in `statePath("karaoke-skips.json")` (`KaraokeScores.skipsFor/toggleSkip`, sanitised on
  read) as a mark `"index:words of the line"`: the index alone points at the wrong line if the lyrics come back from
  another source, the words alone would skip every repeat of a chorus line. A skipped line is all "free" words (nothing
  in it can be lit, nothing in it holds anything up), is never judged, is stepped over by the combo, and is not in the
  song's line total. Left click still seeks.
- **The other voice of a duet.** Two lines whose own spans (`t` .. `t + dur`, not the clamped `lineEnd`) share 0.4 s or
  more are an overlap (`overlapMap`); line-level lyrics with no `dur` never are. One singer takes one voice: a line of
  such a pair that was mostly NOT sung (under half its words) while a partner WAS (half or more) is excused
  (`overlapExcused`) — a miss on it is dropped like a warm-up line's, it does not cut the combo, and the card dims it
  once the song has passed it. Sung half or more itself, or with the partner not sung either, it is judged as normal.
  Not seen on real data: the 244 cached lyrics have 2 overlapping lines in 10,438 (they come from LRC / NetEase); the
  Spicy Lyrics duets are the ones this is for and none are cached here.

**A run has to start from the start to rank** (`KJ.startedFromStart`: before the first line has been going 1.5 s),
and not be skipped about in. Switching Karaoke on mid-song, or seeking mid-run to anywhere but the start, makes
the run UNRANKED (`runValid`, `runWhy` "late" / "skipped"); a seek back to the very start is a fresh run. The
position it checks is where the run BEGAN, not where it was when the lyrics finally loaded (a slow lookup at the
start of a song must not read as "joined late"). The restart's clock and run-start are set explicitly, since the
clock only learns of the seek when the player echoes it back. The old coverage rule stays: at least half the
song's lines, and three.

**The player is held at the end of the song** (`Config.karaokeStayAtEnd`, default on, a Settings row): within 1.2 s
of the track's length, `player.pause()`, so the next song does not start under the results — Next song and Play
again are on the results screen. The check runs BEFORE the "finished" early-return, or a song that finished early
at its last lyric would still roll on. A song that changes anyway is finished from its snapshot, and a run that
covers enough of it is saved quietly.

**The song ends** when the last sung line has run out plus 1.5 s, or the player is held at its end, or stops
there. Then the run is saved and the results screen shows. A run cut short (the song changed, Karaoke switched
off) is saved QUIETLY if it ranks. A run is not saved over a better one: **best** = higher accuracy, then higher
score; the last run and a short history (10) are kept too. Seeking back into a finished song starts a new run.

**What a finished song reads from.** By the time anything reacts to a track change, `Lyrics.lines` is the NEXT
song's. So the held song's lyrics, line count and metadata are snapshotted while it plays (`_snapLines`,
`_snapTotal`, `_meta`, refreshed each second since a cover often arrives after its title), and the finish is done
from the very handler that asks for the next song's lyrics, BEFORE it does.

**The overlays always fit the panel** (`components/FitCard`). The dock draws a panel at its natural size and
scales the content by a zoom, capping the card at the screen's room; a panel has no `maxHeight` to read. The first
results card fell back to a scroll area when it did not fit, which on a short panel left the buttons below the
fold. FitCard lays its content out at its natural size and scales the whole card down to the room it has (the
panel's own size, which is the visible box), following the panel as it resizes; and the optional sections drop out
as the room shrinks (the line graph under 460 px, the judgment bars under 340), so a short panel gets a shorter
card, not only a smaller one.

**Scores on disk** (`KaraokeScores`, `statePath("karaoke-scores.json")` and `statePath("karaoke-covers/")` — one
person's scores, not config, not the repo). The file is read back through `KJ.sanitize` every time: numbers
clamped, strings capped, a rank RE-DERIVED from its accuracy and never believed, a URL must be http(s) or a local
file, a cover name must be the one `coverName` would have made, at most 400 songs (the oldest go). The cover is
cached with `curl` (a declared dependency; argv, no shell; `--proto =http,https,file`, redirects only to http(s))
and only recorded once curl has succeeded; until then the list draws the player's own URL. Songs on file whose
cover never arrived are tried once more at shell start (20 at most). Forgetting a song removes its cover file.
Rank colours are palette roles (SS accent, S focus, A success, B info, C warning, F danger), never hex — on a
monochrome palette the LETTER carries the rank.

**Calibrated on a real recording, not guessed.** Driving the whole game on Vosk's recording, where EVERY word was
heard, the first numbers scored each line "Great" and the run an A (and a timing-only run an F). Two causes, both
fixed: the gate caught only 33 of 60 speech frames (the recording is quiet — speech at RMS 0.010–0.019 against a
0.012 minimum; now `minRms` 0.004 with the periodicity score doing the work, and a voicing "off" level of 0.3
because speech glides dip to 0.3–0.5; now 55 of 60, no false positives in silence), and the timing score wanted
70% of a line's window voiced for full marks, when the window includes a beat either side and (for line-only
lyrics) the gap to the next line. Full marks are now 45%. The same recording now ranks SS (98.5%) with words, S
(93.9%) on timing alone. The gain for the recogniser (`Agc`) likewise follows the periodicity score, not the level.

## Languages (2026-10-17)

Asked for: "support more languages like Portuguese". A speech model is for ONE language, so Karaoke works out which a
song is in and uses that model.

- **Detection** (`KJ.detectLanguage`, once per song): the share of the lyrics' words that are each language's
  function words (accent-folded, as `words()` makes them) — "the and you"; "não você que"; "je tu est" — or, for
  Russian, the script. It needs real evidence (>= 10% and >= 4 words), not a high share of three words: a
  "la la la" refrain is Portuguese, Spanish, French and Italian at once and decides nothing. Pt and Es are told
  apart. A mixed song goes to the language most of it is in. A script with no entry (Japanese, Chinese, Korean…)
  gives none, and the WORDS go off with a note — the English model listening to it would produce nonsense; timing
  alone is honest. `Config.karaokeLanguage` pins one ("" is auto); Media › Settings › Karaoke has the row
  (cycle Auto, English, Português, Español, Français, Deutsch, Italiano, Nederlands, Русский).
- **Supported**: English, Portuguese, Spanish, French, German, Italian, Dutch, Russian (`LANGS`). More is a table
  row and its stop words — Vosk publishes ~30.
- **The grammar keeps diacritics** for those (`grammarWords(text, lang)`). MEASURED on the real
  `vosk-model-small-pt-0.3`: `não você coração está também já mãe amanhã` are all in its vocabulary; folded,
  `nao coracao ja mae` are not — folding would have dropped some of the commonest words in the language. English
  is the one that folds (its vocabulary is ASCII) and puts a dropped g back ("believin'" → "believing"). Measured
  on `vosk-model-small-fr-0.22`: elisions (`j'ai l'amour qu'il c'est`), accents and ligatures are all vocabulary, so
  apostrophes stay inside a word; a hyphen separates (`guarda-chuva` is not a Portuguese word, `guarda chuva` is).
  MATCHING still folds both sides, so an accent the recogniser adds or drops is no mismatch.
- **Models**: `scripts/karaoke-model.sh <language>` (user-run, https from alphacephei.com, no root, writes only under
  `$XDG_DATA_HOME/quicktest/vosk-<code>`, refuses an archive with a path outside its directory or one that is not
  a model; `--list`, `--dry-run`). Looked for, best first (`KJ.modelDirsFor`): `Config.karaokeModelDir` (one path
  for every language, as before), `$XDG_DATA_HOME/quicktest/vosk-<code>` (English also the old `…/vosk`),
  `/usr/share/vosk-models/small-<code>`. The helper restarts with the other model when a song's language changes
  (~0.5 s, between songs). Without a model for the language the header says `Timing only — no <language> model`, and
  Media › Settings shows a **Speech model** row with a Download button (`Karaoke.installModel()`, which runs that
  script; hidden once a model is there — `modelCheck` asks the DISK, `sh -c 'for d; do [ -d "$d" ]…'` over
  `modelDirs`, so it is known before Sing along is on; no button when `Config.karaokeModelDir` is set, that folder is
  the user's). A model that lands while listening restarts the helper onto it. **Portuguese** is `pt`
  (`vosk-model-small-pt-0.3`, 31 MB; Vosk's Portuguese is Brazilian-trained and has the colloquial forms —
  `pra tá né cê tô tava` — with accents). Measured 2026-10-18 on the 44 Portuguese songs in the lyric cache: 40 are
  detected `pt` and sure (the rest are romanised Japanese), and 87% of their word tokens are in that model's
  vocabulary; the 13% that are not are slang (`piroca`, `fuder`, a funk MC's name), English (`yeah`) and the odd
  Vietnamese line. An out-of-vocabulary word can't be heard, so it can't be lit. Bigger models exist
  (`vosk-model-pt-fb-v0.1.1-pruned` 1.1 GiB, `…-20220516_2113` 1.6 GiB) and are not in the script.
- **Words the model cannot hear** (2026-10-18). A model has a vocabulary and a word outside it is not misheard, it
  can never be output: slang, names, an English ad-lib in a Portuguese song — 13% of the word tokens of 40 real
  Portuguese songs against `vosk-model-small-pt-0.3`. Held against the singer they cut the combo on nearly every line
  and capped accuracy: replayed as a PERFECT singer with a recogniser that hears every word it knows, the 40 songs
  scored 87.3% (an A) with 36.5% of lines carrying an unlit word; with the fix, 100% and 7%. At 85% word recognition,
  82.0% -> 95.3%. The helper reports them with each grammar reply (`oov`, from `Model.vosk_model_find_word`, ASCII or
  not); `Karaoke._oov` keeps them folded like the tallies' words and forgets them when the helper restarts (a
  different model, a different vocabulary). In `karaoke.js` such a word is FREE: lit together with the heard word
  beside it (before and after; the cursor steps over the trailing ones), not a lookahead step, never a match itself,
  passable in a gap-fill; a line of only free words is not judged in a words run and does not break or end a combo
  (`comboRun`/`comboSurvives` take the list). Known gap: the fold can make an unhearable word collide with a hearable
  one (`pró` vs `pro`), which only makes that word free. Never run on a real recording.
- **A bigger Portuguese model is not a drop-in.** `vosk-model-pt-fb-v0.1.1-pruned` (1.1 GiB) has a STATIC graph
  (`graph/HCLG.fst` + a 1.4 GB `rescore/G.carpa`, read off the zip's directory 2026-10-18) and no `HCLr.fst`/`Gr.fst`, so
  the runtime lyric grammar — measured above as the biggest lever on accuracy and speed — would be ignored and it
  would run free-form. Not built; the unresolved call is whether free-form with a better acoustic model beats the
  small model with the lyric grammar, which can only be settled with a recording.
- **Not language-aware yet**: `soundKey` (the sound-alike matching) is English-shaped and only keys plain Latin
  letters — for the others, matching is exact (after folding) plus spelling closeness, which works but is not
  tuned; the weak-word list for gap-filling is short words plus a few English ones; the UI strings are English
  (the shell has a `Translation.tr` system; Karaoke's strings are not in it yet).

## Detection (reworked 2026-10-17)

**What a frame measures** (`scripts/karaoke.py`, `Analyzer`): the level in the SINGING BAND (120 Hz–3.5 kHz),
not the raw level, and `voicing` — the strength of the strongest period between 100 Hz and 1 kHz (a
normalised autocorrelation, unbiased for the window). Both from ONE FFT per frame (~0.03 ms). Needs numpy;
without it `rms` is the plain level, `voicing` is absent and the gate judges level alone.

**Why:** a level alone cannot tell a voice from a fan. Measured on synthetic signals: a voice-like signal
scores ~1.0, a vowel 10 dB over noise >= 0.88, white noise never passed 0.46, smooth low-passed noise (a
rumble) reached 0.69 — hence the gate asks for BOTH loud and periodic, with a hysteresis (on at 0.55, off at
0.38). A steady mains hum is truly periodic: only the slow noise-floor learning (~90 s) handles that one.

**Faster:** 30 ms frames (was 50), the gate lights on the first loud periodic frame and goes dark ~160 ms
after you stop (was 240), Vosk's partial is asked for every second frame (~60 ms) — a word is taken once two
partials agree on it, so this is most of the lag between singing a word and it lighting.

**Close enough to the ear counts** (`sameWord`, `closeness`, `soundKey`): a recogniser hears a sung word as a
neighbour of it ("wheel" for "will", "rack" for "rock"), so words are compared by how they SOUND as well as
how they are spelt. `soundKey` boils a word to its consonant skeleton: b/p, d/t, g/k, v/f, z/s fold (the
pairs a voice and a mic confuse), silent letters go (knight, thought, lamb), vowels go (the least stable part
of a sung word), sh/ch/th are one sound each. Equal skeletons score 0.92 (never 1, so an exact word still
beats a sound-alike); a near-miss counts only in a skeleton long enough to stay specific (0.75 — one edit
in a three-letter key let "golf" pass for "alpha"); spelling alone at 0.66. A word of three letters or
fewer is only taken on its sound ("know" ~ "no", but "the" is not "she", and a bare vowel is not every
vowel). English-shaped (what Vosk's small English model hears); anything else is compared by spelling.
Deliberately lenient (the user's ask): "sing" ~ "song", "love" ~ "leave" count. Tighten `closeness`'s bars
if it lights words you did not sing.

**The matcher** (`karaoke.js`, `matcherHear`): a forward-only CURSOR through the lyric words. It replaced an
alignment redone from scratch on every partial, which had a real bug — when two lines share words ("we will
rock you" twice), the words already sung still sat in the recogniser's utterance, matched the NEXT line's
identical words just as well, and lit them. Now each heard word is consumed once, in order: matched against
the next 5 lyric words from the cursor only, never backwards, and of those in reach the BEST wins (closeness
less 0.06 per word skipped — a sound-alike at the cursor doesn't steal a word sung exactly two on); a hit
moves the cursor past it; a partial's last word is taken only once seen unchanged twice (a final takes all);
the cursor stays within a line of the song (`matcherSync`). Tested with the exact repeated-line case, and a
line only opens once the song is near it (above).

**Gain for the recogniser** (`Agc`, karaoke.py): a faint voice gives a speech model little to work with, and
singing into a headset is often faint. The audio handed to Vosk (only — the levels the gate reads are
measured before it) is eased up toward a target level, capped at 6x, moving only while a voice is there and
holding in silence, clipping rather than wrapping.

**Smoother:** `Karaoke.glow` follows `lit` once per FRAME (quick to light, 50 ms; slow to fade, 280 ms) and
sleeps when idle. A fixed-length Behavior retargeted at the ~33 Hz level
rate is what read as flicker. The underlines wipe in rather than pop.

## Recognition — measured, not guessed (2026-10-17)

The user said it was "not fast enough" and "sometimes doesn't detect my words". With the real
`vosk-model-small-en-us` and Vosk's own 8 s sample recording (`alphacep/vosk-api`,
`python/example/test.wav`, fetched to a scratch directory, never into the repo) the loop was replayed and
measured.

**Vosk itself is not the slow part.** A word shows up in a partial result between ~0.06 s before it ends
and ~0.27 s after; a call costs ~3 ms (~0.03 ms for a partial). The lag the user felt was the pipeline
around it.

**A grammar of the lyric words is the biggest lever on both accuracy and speed.** The helper builds the
recogniser with the words of the lines around now (`grammarFor`: each line as a phrase, each word alone,
plus `[unk]`). On the sample, free-form misheard "nine oh two i no" as "nah no to i know"; with the grammar
it came out exactly, and words appeared 0.1–0.25 s EARLIER. Speech that is not in the grammar comes out as
`[unk]` — it does not hallucinate lyric words. Replayed end to end through the real helper loop and the
real matcher: lines lit 5/5, 5/5, 5/5 (free-form: 5/2/4), on average 0.06 s after each word ended (free-form
0.14 s, worst case 0.63 s).

Four traps, each found by measuring, each now in code:

1. **`SetGrammar` on a running recogniser ABORTS THE PROCESS** (Kaldi fatal error, exit 134 — not a
   catchable Python exception). It is never called. A fresh `KaldiRecognizer(model, rate, grammar)` takes
   ~0.2 ms and cannot do that. The helper dies without cleanup if this is ever reintroduced, which is why
   the service also restarts it (below).
2. **A swap mid-sentence loses the sentence** ("one zero zero zero one" in flight came out "zero one"). A new
   grammar waits for a GAP — right after a final, or while no words are in the hypothesis for ~240 ms — and
   is forced in only after `FORCE_MS` (8 s), for singing with no pause. The grammar covers a line behind and
   three ahead and is re-sent only when the song is within a line or two of its edge (`grammarStale`), so
   swaps are rare.
3. **The helper de-duplicated partials, so the LAST word of every line waited for the final result** (~0.7 s
   later): the matcher takes a word once two consecutive partials agree on it, and an unchanged partial was
   never sent. It is now sent every frame it is non-empty. This was most of "not fast enough".
4. **A stray word at the end of a partial lit the next line.** Vosk's partial for one line briefly carried the
   FIRST word of the next; once partials were confirmed promptly it lit that line's word and pulled the cursor
   into it, stranding the real last words (line 2 went 5/5 → 3/5). A line's words can now light only once the
   song clock is within `OPEN_LEAD` (0.8 s) of it (`lineOpen`), and a closed line ends the search. This also
   hardens the repeated-line fix.

Words are only lit while you are voicing (the gate was true within `voiceHoldMs`, 800 ms): the recogniser
can put a word to a breath (measured: a stray "one" on quiet noise). Out-of-vocabulary lyric words are just
ignored by Vosk (not an error, not a crash); its vocabulary is lowercase; `[unk]` is stripped before matching.

**Gap-fill and lookback** (`matcherHear`): a recogniser drops small words, so a word of three letters or fewer
(and a few common longer ones) between two heard words in the same line, up to two, is taken as sung; the
small first word of a line is filled once the cursor has left the previous one. The matcher can also step back
up to four UNLIT words in its own line, so one wrong jump forward cannot strand the real words behind it —
never into an earlier line, never onto a lit word.

**Other engines** (asked 2026-10-17): whisper-cpp (official repo) is batch, ~1–2 s behind on CPU, cannot be
told what to listen for, invents text on silence, and is weak on singing. Cloud services (Google, Azure,
Deepgram, OpenAI Realtime) are the most accurate on speech but would send the live microphone to a third
party, need keys and billing, and only offer weak "hint" lists, not a hard constraint — not for a published
shell without the user's say-so. A bigger Vosk model (`vosk-model-en-us-lgraph`, AUR) is a drop-in through
`Config.karaokeModelDir` and the first thing to try if words are still missed — NOT measured here. sherpa-onnx /
Parakeet are streaming and local but not packaged for Arch. The helper's stdin/stdout protocol does not depend
on Vosk, so an engine can be swapped later.

**Underlines that vanished at a line change** (reported three times). The ROOT CAUSE, found by reading how the card
builds its rows: `visibleRows` is a NEW array every time the current line changes, so the Repeater destroys and
rebuilds every row — and every row's `KaraokeMarks` — at each line switch. A mark placed itself with
`positionToRectangle()`, a plain function call that notifies nothing. While you sang, a mark was created at the
first hit, long after its row's layout had settled, so it drew. After a rebuild, marks were created already
knowing their flags, in the same instant as the new TextEdit — before it had a width or had laid anything out —
read an empty rectangle, and never read it again. Visible exactly as long as its line was current. Now a position
is read through `rectAt()`, which depends on the layout's width, content height and length (what LyricGlyphs
reads for the same reason), refuses out-of-range positions (a stale index logs a QTextCursor error per mark per
frame), and is re-read once after creation. The marks no longer depend on Karaoke being on at all: they stay —
through a line change, a seek, the clock stepping back, Karaoke being switched off — until a different song plays
or a new run starts.

Two earlier fixes stay, because they were real too: the song clock steps BACK a few tenths now and then
(`MediaPosition` re-anchors straight to the player's position when it drifts > 0.25 s, and the Spotify-bridge
branch has no smoothing), which read as "the song went back a line" and — as a seek — dropped what had just been
sung (`KJ.stepLine`: a step back is a seek only if it is more than a line or more than 1.5 s; tested with a clock
jittering across a boundary); and the whole memory was reset on any change of `Lyrics.trackIdFor`, which includes
metadata that arrives late (a NEW SONG is now only a change of artist + title, and the memory is kept per song for
the last few). `qs ipc … call karaoke status` prints `sung=[line:lit/total,…]`.

## The microphone

`scripts/karaoke.py`, only while on: `pw-record --raw --rate 16000 --channels 1 --format s16` → frames →
JSON lines on stdout (`ready`, `level`, `text`, `grammar`, `error`); JSON lines on stdin (`grammar`, `quit`; end of
input is NOT a quit). If it dies on its own the service starts it again, up to three times a minute, then says so. The service restarts it when the default source
changes (`_cycling`, the CavaStream shape — a `Process` that exits by itself stays exited while its
`running:` binding still reads true).

- **No audio is written anywhere.** It goes pw-record → memory → gone. It is a real PipeWire input stream,
  so the microphone indicator and the Recording list show it, on purpose.
- It sets `PR_SET_PDEATHSIG` on itself and on pw-record: the shell dies without cleanup on a reload, and an
  orphan would hold the mic open.
- **Headphones or it won't run.** The mic hears the song otherwise, and a cell lit by the music is a match
  that means nothing. `KJ.isHeadphones` reads `device.form-factor` (headphone / headset / hands-free) or the
  icon name off the DEFAULT SINK's PipeWire props; unknown counts as not (refuse, don't guess).
  `Config.karaokeSkipHeadphoneCheck` is the way past a device that reports wrong. Measured here: the
  Arctis Nova 3 node says `device.form-factor = headset`.

## Words need two optional packages

`python-vosk` (official `[extra]`) and a model: `vosk-model-small-en-us` (AUR, installs to
`/usr/share/vosk-models/small-en-us`). Both are in `scripts/install-dependencies.sh`'s optional table
(`vosk`, `voskmodel`) — not yet in Settings › Setup's wizard UI. Any model from alphacephei.com/vosk/models
works, in the language of the lyrics. `python-numpy` is recommended (the voicing score).

The model is looked for, best first: `Config.karaokeModelDir` (if set), `$XDG_DATA_HOME/quicktest/vosk`,
`/usr/share/vosk-models/small-en-us` — built in ONE place (`Karaoke.modelDirs`); the helper takes the first
that exists. `Config.karaokeWords` turns words off. Without both packages the module still runs on timing
alone, and Settings says what is missing (`Karaoke.modeNote`).

## The lyrics

`Lyrics.loadFor(player)` is the request a lyrics view makes when its player or track changes — it used to
live in `OverviewLyrics._reload` and moved into the service so Karaoke asks exactly as the card does and
needs no card on screen. The clock is a `MediaPosition` (built in a Loader only while on) plus
`Lyrics.offset`, the user's own nudge — if it lights late or early, that is the knob (the card's footer
stepper).

## Not verified — check these first

None of this has run. In rough order of how likely each is to be wrong:

1. **pw-record's flags and the pipe.** `--raw … --latency 50ms -` and `--target <node name>` are from
   `pw-record --help`; the stream has only been fed in-memory fixtures. `python3 scripts/karaoke.py` by hand
   should print `ready`, then a `level` line every 30 ms.
2. **Singing.** Vosk and the matcher are now verified against a real recording of SPEECH, end to end (above), not
   against singing: sung vowels are longer, pitched and slower, and the recogniser's behaviour on them is
   unmeasured. The sound-alike bars are the thing most likely to want tuning against real sung output.
3. **The gate's thresholds** (`GATE`: minimum 0.012, 2.6x the floor, 0.55 / 0.38 voicing) come from
   synthetic signals, not a real mic in a real room.
4. **Singleton hosting a Loader / MediaPosition.** Drift hosts Items in a singleton the same way, but
   MediaPosition has had GC trouble before (`QV4_GC_TIMELIMIT`, shell.qml).
5. **`Process.running = false` stops the helper** (it handles SIGTERM; whether Quickshell sends it is
   assumed from the existing helpers).
6. **The underline positions** (and that they persist across a line change) — QML that has never been drawn.
7. **How lenient is lenient enough.** The sound-alike bars were set against a list of word pairs, not against
   a real recogniser hearing real singing; they will want tuning against what Vosk actually returns.
8. **The game screens** (HUD, results, scores) — QML that has never been drawn. The animations are one timeline with
   tokens from Motion; whether they LOOK right is unseen.
9. **Finishing a real song.** The end-of-song detection, the finish-on-track-change from a snapshot, and the cover
   fetch are logic reasoned from the code and the pure parts tested; none has run against a real player changing
   track. `qs ipc … call karaoke status` shows `finished=`, `result=`, `song=`, `total=`; `qs ipc … call
   karaokescores status` shows the table.
10. **The 45% timing bar** was calibrated on one recording of speech. Singing may want it moved.
11. **Other languages with a voice.** Detection is tested on sample lyrics, and the Portuguese and French vocabularies
    and the download script were tested against the real models; but no Portuguese (or other) SINGING or speech has
    been run through the loop, only the vocabulary and the grammar build. The sound-alike bars are English-tuned.
12. **The mid-song warning and the countdown restart** — the pure rule is tested; the overlay, the pause-seek-play
    sequence against a real player, and the countdown's timing have not run. Some players ignore a seek while paused.
13. **Holding the song at its end** — `pause()` within 1.2 s of the track's length is reasoned from MPRIS, not seen:
    a player that reports its length late or loosely may be paused early or too late to stop the next track.
14. **The mods' numbers** (the 85% / 90% / 0.05 s / 0.3 s / 65% / the multipliers) are reasoned, not tuned: no one has
    played a Time-Hell run. Hidden Lyrics is an opacity on the card's rows (`OverviewLyrics`), so it applies to every
    surface that draws the card while a run with the mod is on — never seen drawn.
15. **SS+** needs every judged line to be exactly 1.0 points. With words that means >= 70% (90% on Hard Rock) of every
    line's words AND the timing at full marks on every line; whether that is reachable by a real singer, or too
    easy / too hard, is unknown.

## Scope decisions

- No grammar-restricted recognition (it would hear more and light words you did not sing).
- No per-syllable word timing in the score (a recogniser's word times are too loose to compare).
- No pitch scoring — there is no melody to compare to.
