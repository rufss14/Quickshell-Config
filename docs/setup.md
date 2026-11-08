# Setup

One plan, one button, shown two ways over the same state:

- **First-run window** — `WelcomePanel.qml` (frame) hosts `SetupWizard.qml`: the paged layout (Welcome, Packages,
  Morphing system, Hyprland, Integrations, Colours, Review). Pages only *choose* (a tick per step); the Review page
  has the password, the one button, the run and the recap. The user preferred pages to a single list (2026-10-18),
  so the first version of this rebuild — one list — was kept only for Settings.
- **Settings › Setup** — `SetupPage.qml` embeds `SetupFlow.qml`, the same plan as one checklist
  (Recommended | Custom), for coming back to it later.

Shared pieces: `SetupStepRow` (a tickable step), `SetupPassword` (root, asked once), `SetupRun` + `SetupRunRow`
(timeline and recap). Neither host holds logic.

Rewritten 2026-10-18 from a seven-page wizard (about fifteen install buttons, one job at a time, a password
box in the chrome, a job switch in the window) plus a read-only status page. **Built and statically checked,
never loaded** — see "Untested" at the end.

## The look

Built from the panels' vocabulary, not a form: cookie plates (`SetupCookie`, on `ShapeBox`, so `Config.iconShape`
applies), cards that spring in one after another (`PopIn`, replayed each time a page is shown) and lean toward the
pointer, a page that rises in (`ViewEnter`), a `RadialGauge` for "how ready is this machine", a progress strip whose
current stop opens to name its page (each stop is a link), scan/preflight chips, the live palette as a strip of cookies,
two big choice cards for Hyprland, a 2×2 grid for the optional extras, and a Review page that draws the plan as a
timeline with three stat cards (steps, time, password). Nothing decorative that the logic doesn't back.

## Added 2026-10-18 (second pass)

- **"What will this do?"** on every step card: `touchesFor()` in `setupplan.js` lists the commands, files, network
  and root requests of each step, written from the scripts' own headers (tested: every step must say something).
- **Copy report** in the recap: `formatReport()` — machine, plan, how each step ended, a failure's last 12 lines;
  the home directory is shown as `~`, no secret can be in it (the password is never stored).
- **Undo for the Hyprland step**: `scripts/restore-hypr-config.sh` (`--list`, `--restore [PATH]`, `--restore-minimal`;
  tested by `scripts/test-restore-hypr.sh`). Restoring sets what is there aside (`hypr.before-restore.<time>`), never
  deletes, and only restores from `hypr.bak.<digits>` next to the config. The card is `SetupRestore`, a two-click latch;
  it is on the Hyprland page and in the recap after the step ran.
- **Health check** (`health()` in `setupplan.js`, `Setup.healthIssues`): what has drifted since setup — a plugin that
  stopped loading, another notification daemon, nothing starting the shell, no binds, no palette, two password
  agents, a blurless translucent bar. Listed on the welcome page once `Config.setupSeen` (a re-open), each finding
  a link to the page that fixes it; Settings › Setup has a "Health check" button that opens it.
- **Style page** (light/dark, icon shape, bar corners, spacing, floating cookies, animations): the shell's own
  preferences, written as you click, so the shell behind the card changes at once.
- **"Your keys"** on the all-set page: the launcher/overview/dock/game-mode binds read from the user's own
  Hyprland config (`HyprConfig.binds`), not assumed.

## Layers

| Layer | File | Job |
|---|---|---|
| Logic (pure, tested) | `services/setupplan.js` | `parseScan`, `compat`, `blockers`, `hyprMode`, `catalogue(facts, mode)` → steps, `defaultSelection`, `buildPlan(steps, selected)`, `etaText`, `explainFailure`. `bun scripts/test-setupplan.js` (93 checks). |
| Integration | `services/Setup.qml` | Probes (Hyprland files, packages, app theming, rivals) + the scan; assembles `facts` → `steps` → `plan`; the queue runner `startPlan()`; job functions; `startJob(id)` is the one id → function switch (plus `theme-*` and `pack-*`). `qs ipc -c ~/.config/quicktest call setup status` dumps the state. |
| Presentation | `modules/onboard/SetupWizard.qml`, `SetupFlow.qml` + the shared rows | Wizard: 7 pages. Flow: stages `scan` → `plan` → `run` → `done`, Recommended \| Custom. |
| Scripts | `scripts/setup-scan.sh` (read-only machine scan), `install-aur-helper.sh` (paru-bin), `install-dependencies.sh`, `theme-setup.sh`, `build-blobs-plugin.sh` | |

## The plan

`catalogue()` lists every step with a state: `done` / `todo` / `blocked` (with a reason). The recommended
steps that are still `todo` are ticked. `buildPlan()` pulls in dependencies (an AUR step brings the AUR helper,
which brings the base tools), drops anything blocked and everything that needed it, and keeps catalogue order.
The runner skips a step whose dependency failed and carries on with the rest; every failure goes through
`explainFailure()` (pacman lock, 404 mirrors, keyring, disk, wrong password, build errors) before falling back
to "the log has the details".

Hyprland: if you already have a config, the default is *one added file* (`quicktest.lua`), never replacing it;
the bundled config replaces `~/.config/hypr` (backed up first) and is the default only when there is none.
Custom shows the choice (`Setup.hyprModeChoice`).

## Feature packs (2026-11-08)

`install-dependencies.sh` used to install every feature's packages as "core". Now `PACK_PKGS` holds the
official-repo packages one feature needs (`clips`, `gamemode`, `blob`, `ddc`, `beatsync`, `discordkeys`,
`depth`), and each is a step: `clips`/`gamemode` ticked in "Make it yours" (Packages page), `ddc`/`beatsync`/
`discordkeys` unticked extras (Integrations page). The blob step runs `pack-blob` (cmake, qt6-shadertools)
before it builds. `depth` (uv) is not a step: the depth clock's own blocker asks for it. `flatpak` and
`reflector` are no longer installed at all (see the script's comment). `Setup._packProbe` reads `--packs`
and reports `key=installed=pkg,pkg`; job `pack-<key>` runs `--pack <key>` elevated like `--core`. A plain
`install-dependencies.sh` (setup.sh) installs `DEFAULT_PACKS` so the CLI and the wizard agree.
Built, tested (`node scripts/test-setupplan.js`), never loaded.

## Root, asked once

`plan.root` says whether any step needs it. Then either:

- a password typed once in the plan screen, handed to every job on stdin (`sudo -S`, guarded by `SudoLock` /
  pam_faillock — wrong passwords stop the whole run rather than burn three attempts per step), or
- with the field empty and a polkit agent running (`facts.polkitAgent`, which includes the shell's own when
  `Config.polkitAgent` is on): `pkexec` for the root steps. `theme-setup.sh` honours `SETUP_ELEVATE=pkexec`;
  the AUR helpers get `--sudo pkexec`. The honest cost: one system dialog, plus roughly one per AUR build.

The password is never stored; `Setup._planPw` is cleared when the run ends.

## Gotchas found on the way

- `scripts/install-dependencies.sh --core` used to install `otf-codenewroman-nerd` from an Arch Linux Archive
  URL pinned to one version, and `IgnorePkg` it. Gone: it installs from the repos only if missing.
- The Vulkan driver was hardcoded to AMD; `--vulkan` now reads the GPU from sysfs (lspci fallback), skips
  nouveau when the proprietary NVIDIA driver is in use, and falls back to `vulkan-swrast`.
- `--official` is one pacman transaction; one bad name used to fail all 59. It retries per package, unless
  the failure is a lock, the network or the disk.
- The plugin installs system-wide (`/usr/lib/qt6/qml/Quicktest/Blobs`), not under `$XDG_CACHE_HOME` — CLAUDE.md
  said otherwise.
- `readonly property real left` in a layout is a FINAL-property hard failure (`check-qml-final.py` caught one
  in the first draft of SetupFlow).

## Bugs this turned up

- **`gtk3_refresh` could leave GTK on Adwaita-dark for good** (`scripts/wave-lib.sh`). It flips the `gtk-theme` key to
  another theme and back, remembering what it read; two refreshes overlapping (colour changes close together) made
  the second read the first's temporary value as the user's theme and keep it — adw-gtk3 gone, and Settings › Setup
  then truthfully said "GTK is not set up". Now one refresh at a time (`flock`) and the real value is written down
  before the toggle (`$XDG_STATE_HOME/quicktest-gtk-theme-real`) and put back by the next refresh if a toggle never
  finished. `bash scripts/test-gtk3-refresh.sh` reproduces the race (the old code fails 4 of 7).
- A scheme "applied to all workspaces" was stored as ten per-workspace entries, which outrank the shell's palette, so
  nothing applied afterwards showed. Every-workspace is now the shell's own scheme (the wallpaper picker's rule), an
  Apply releases per-workspace schemes, and the library says so with a Clear button (`ColorScheme`).

## Untested (needs a real run by the user)

Everything visual; the polkit path (`pkexec` with and without the shell's agent); `install-aur-helper.sh`
end to end (only the "already present" exit was run); a full plan with real installs; the colours step
(`Wallpaper.reapplyPalette()`); the recap's restart note. After pulling this in, ALT+Q (new files and inline
components don't hot-reload).
