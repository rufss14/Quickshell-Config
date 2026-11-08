# System updates

Moved from CLAUDE.md; the project rules there still apply.

## System updates

`scripts/update-run.sh` (detached runner) → `services/Updates.qml` →
`modules/panels/UpdatePanel.qml` (the bar pill's popup) and
`modules/settings/pages/UpdatesPage.qml` (the richer settings view). The bar pill
and the desktop tile open the panel through `UiState.updateRequestId`.

- The runner is **detached on purpose** (`setsid`, reparented to init): reloading
  or killing Quickshell must never kill a live pacman transaction. Output goes to
  a log FILE, not a pipe, so a fresh `tail -F` can reattach after a reload.
- **The lock is `flock`.** The old "lock" was `printf $$ > lockfile` — a write,
  not an acquisition, so it refused nothing and two `pacman -Syu` ran at once
  (truncated log, shared stdin FIFO handing the password to a coin-flip, stranded
  `db.lck`). flock is kernel-held and released on crash or reboot, so there's no
  stale-lock logic. Test it with `flock -n -s "$LOCK" true`, never
  `kill -0 $(cat "$LOCK")`.
- The upgrade is **non-interactive, in numbered phases** (`:: [n/N] …`): pacman,
  then `<helper> -Sua`, then flatpak. `--noconfirm` is deliberate — an aborted
  upgrade is safe, reversible and reportable; a half-answered prompt on a stdin
  nobody owns is not. Don't "fix" it back to interactive.
- The phase markers are load-bearing: `state.inHooks` latches, so without a phase
  boundary to clear it the first phase's post-transaction hooks swallow every
  later phase.
- **A run does NOT share one process group.** `pty.spawn` calls `setsid`, so one
  run spans four PGIDs. `kill -TERM -$PGID` reaches the wrapper and nothing else.
  Cancellation walks the real tree (`update-run.sh cancel`) and deliberately
  cannot signal root-owned pacman: closing the PTY makes it exit through its own
  cleanup rather than being killed mid-transaction, which is what strands
  `db.lck`.
- `/var/log/pacman.log` can contain NUL bytes (residue of a killed pacman), and
  GNU grep then classifies it as binary and silently suppresses every match.
  Always `grep -a` on that file.
- **The sudo keepalive runs INSIDE the PTY**, prefixed onto the job's own command.
  sudo's `tty_tickets` (default on) keys the credential per controlling terminal,
  and the runner is `setsid`-detached with no terminal. Run the keepalive from the
  runner and it refreshes a ticket nobody uses. It still needs `exec 9>&-` (the
  flock fd is inherited that far down) and a `trap … EXIT` to kill it.
- The full upgrade's flatpak phase is **`sudo flatpak update --system -y`, not
  polkit**. By then `sudo -v` has cached the credential the user typed; polkit
  can't know that, so plain `flatpak update` raised a second password dialog
  mid-upgrade. It covers both scopes (as root the "user" installation is root's
  own empty one). `installSelected()` still uses polkit *on purpose* — a selection
  can be flatpaks alone, with no sudo in the run to reuse.
- After a run, counts refresh in **two passes — 3s then 90s**. The late pass is
  the safety net if the early read caught a database mid-write.

- **`__QS_RUN__ <seq>` — the fix for "it said it updated when it didn't".** QML
  starts its `tail -F` the moment it fires the launcher, before the runner has
  taken the lock and truncated the log — so the tail first replays the PREVIOUS
  run's whole log, trailing `__QS_DONE__` and all. That stale sentinel was parsed
  as *this* run finishing (auto-close, success notification), and it wiped the
  remembered password, so the real sudo prompt then asked a second time. Now every
  `_launch` bumps `_runSeq` and passes it to the runner, which echoes it back as
  its first log line (`__QS_RUN__ <seq>`). QML drops everything the tail gives it —
  log lines, `__QS_DONE__`, prompt detection — until it sees its own seq.
  Reattaching to a genuinely surviving run is ungated (the log there really is the
  current run's).
  **The token is `<Date.now()>.<counter>`, not the bare counter** (2026-10-06): the
  counter restarts with every shell, so every session's first run was `1` — the same
  as the stale log from the previous session's first run. The gate opened on the old
  log, its `__QS_DONE__` wiped the password and stopped the tail, and the real sudo
  prompt sat unwatched: "it fails and asks for the password again".
- **"Finished" is not "nothing left".** `pacman -Syu` exits 0 when its packages
  are held or a phase no-op'd. `_handleDone` reports a failure immediately (the
  code is authoritative) but holds a clean exit for a 4s `resultNotify` timer,
  which reads the post-run recheck: "installed successfully" only if nothing's
  pending, otherwise "Update incomplete". The panel's `trulyDone` gates the
  auto-close the same way.
- **Holds** are `Config.updateHold` (persisted, defaults `[]`), spent as
  `--ignore` on the `pacman -Syu` / helper command. NOT pacman's `IgnorePkg` — that
  needs a root edit to `/etc/pacman.conf` (a typo bricks pacman) and never
  expires. Flatpak is excluded (`flatpak update` has no exclude flag), so held
  Flatpak names don't count toward `heldPending`.
- **Arch news.** `Updates.refreshNews()` fetches the Atom feed (curl, 30-minute
  floor); `newsUnread` is true when the newest item post-dates `lastUpgrade`. The
  rule is blunt on purpose — we can't parse "needs a manual step" out of a
  headline, so if it's newer than your last upgrade, show it and link it.
- **Run summary** (`runUpgraded` / `runInstalled` / `runRemoved` / `runSizeText`)
  is tallied from the same package lines the progress parser reads, plus pacman's
  `Total Download Size:` line.


## Shell updates (Quicktest itself)

Not packages — new releases of this shell. `scripts/release.sh` (the maintainer's
`qtrelease`) publishes; `services/ShellUpdate.qml` checks and offers;
`scripts/shell-update.sh` installs. UpdatePanel shows it as a square gear button BESIDE the
sudo password field (`ShellUpdateButton`, both views): spins while checking or
installing, fills when a release waits, red after a failure; click = Check or
Update. Its words borrow a line that's always there (the header subtitle, or
the caught-up view's "last updated" line): shown on hover / while checking or
installing, flashed ~4.5s for a clicked check's answer, a new release or a failure.
NOT a caption of its own — one that came and went changed the panel's height, and
while the card sprang after it the content ran over the card's bottom edge. Settings → Updates has the
full card (`components/ShellUpdateCard`: notes, release link) plus the schedule
toggle. Both draw Quickshell's gear from `assets/logos/quickshell-mono.svg` through
`TintedIcon` (`PanelButton.iconSource`), so it wears the palette — the full-colour
mark would stencil to a solid square. The bar pill's badge counts a pending shell
update as one.

- **Publishing is separate from syncing, on purpose.** `qtsync` only refreshes
  `~/.config/quicktestPUB`; you test that copy, then `qtrelease <ver>` ships it AS
  IS (it warns if the source tree has drifted, never syncs for you). It bumps
  `Config.version` in both trees, commits the copy, builds the tarball with
  `git archive`, signs, pushes the copy to GitHub `main`, tags, and creates the
  release. First run needs `--force-main` (the copy's history is new).
  Claude drives it with the `/release` skill (`.claude/skills/release/`): phase 1
  syncs, checks, writes notes, fixes README.md, then STOPS for the user to test;
  phase 2 runs `release.sh … --yes` only on their explicit go. `--yes` never
  asks — no notes, a drifted copy, or a key that would prompt (not in ssh-agent)
  each fail before anything is written.
- **Signed, and the trust anchor is the INSTALLED copy.** Assets are
  `quicktest.tar.xz`, `SHA256SUMS`, `SHA256SUMS.sig` (`ssh-keygen -Y sign`,
  namespace and identity `quicktest-release`). The installer verifies against
  `release/allowed_signers` from the copy already on disk, never the downloaded
  one. Lose `~/.ssh/quicktest-release` and existing installs can't auto-update.
  Releases before v0.4 have no signature or `.release-files` and are never offered
  (`shellupdate.js` requires all three assets).
- **What an update writes.** Shipped files are replaced (new inodes, so a running
  script keeps its bytes); files the old `.release-files` listed and the new one
  doesn't are deleted; nothing else is touched (secrets, `theming/`, builds).
  `presets/` and `colorschemes/` are user libraries (Config's JsonStores write
  there): a release only ADDS files to them, never overwrites or deletes.
- **`git archive --add-virtual-file` ignores `--prefix`** (measured, git 2.56):
  the path must be spelled `quicktest/.release-files` or the installer refuses
  the archive. And `-c tar.umask=022`, or files ship group-writable.
- **Hot reload is OFF during an install.** Quickshell reloads on every changed
  file with no debounce (`EngineGeneration::onFileChanged`), so the service sets
  `Quickshell.watchFiles = false`, the detached installer copies, then restarts
  the shell via `reload-quickshell.sh`. It closes its flock fd first — the
  restarted shell would otherwise inherit it and hold the lock forever.
- **A git checkout is blocked** (`blocker`): the dev tree must never overwrite
  itself from a release, and a clone updates with `git pull`.
- Checks: `bun scripts/test-shellupdate.js` (versions, response parsing),
  `bash scripts/test-shell-update.sh` (the real installer vs signed file://
  releases: good, wrong key, tampered, mislabelled, git checkout).


## The update panel, in the shell's recipe (2026-10-12)

`UpdatePanel` rebuilt to the style the wallpaper, media, colours and clock panels wear. **Nothing it does changed**: the state object, the
selection rules, the prompt path, the password handling, auto-close, the keyboard-focus rules (`wantsKeyboard`), the shell-update gear's
words and every `Updates.*` call are the same code. What changed is how it looks, how it moves, and what it tells you.
- **Style.** A `ChipTray` header (refresh and the setup shortcut; while running, the log and Cancel); flat section cards (`Colors.section`, so
  the cookies show through); a `SegmentSwitch` where there is a choice between views of the same thing (the pending list's source, the
  activity's Output | Simple); pill `InputField`s — the sudo field is `InputField { secret: true }` now (it types the shell's key click like any
  field; `Sfx.typed` plays a cue per key and stores nothing); a filled `ChipButton` for the one thing to do and an outlined one for the other;
  `ViewEnter` / `PopIn` for each view arriving; and the shell's cookie (`Scallop`) with a tick on the caught-up view and a tick or alert on the
  finished receipt. `ChipButton` gained `iconSource` (an SVG stencil) for the Quickshell gear.
- **Rigid layout.** Pinned to the top at its own height, every layout child stating `fillHeight`, and `implicitHeight` from the content (capped
  at 600): the fixed 188 / 210 / 400 per state are gone, so a prompt can never be clipped and the header does not slide while the dock springs
  the card.
- **The pending list** (still folded by default): a source switch with counts (hidden when there is only one source), a name filter once there
  are more than eight (`updatefmt.js matches`: every word, any order), a tick-all for the AUR / Flatpak ones shown (official can still never be
  ticked), and each row says how big its jump is — `bump()`: major / minor / patch / rebuild / git / new, by the FIRST place the versions differ
  (epoch or first number = major, second = minor, then patch; only the pkgrel = rebuild; r1234.abc or a date = git) — as a coloured dot, spelled
  for major and minor, sorted biggest first. Under the pointer, a hover tray: open the package's page (archlinux.org search, the AUR page or
  Flathub; the name is URL-encoded) and hold.
- **A run** shows "Step 2 of 3" as segments, a roughly-how-long estimate once it has something to extrapolate from (`etaText`: after 20 s and a
  fifth of the way, worded "about", silent past two hours), and can be **cancelled from the header** (two-step; it was only reachable from a
  prompt). A **finished run is a receipt**: a cookie with a tick (success), a warning (exit 0 but updates remain) or an alert (failed), what
  changed and the download size, Reboot (two-step, only if a kernel or graphics module moved), **Copy log** (the whole run's log to the clipboard,
  for a bug report) and Close.
- **"Checked 3 min ago."** `Updates.lastChecked` / `lastCheckedText` (set when a check finishes without an error) is in the header subtitle and
  the caught-up line, so "nothing pending" can be trusted rather than being a number that might be nine minutes stale; the caught-up view
  also has Check now, and the setup shortcut (its header is hidden).
- Tests: `bun scripts/test-updatefmt.js` (43). Checked: the usual static suite. NOT run: a real update, a real prompt, the cancel path, the
  gear, a Vencord patch — none of it can be exercised without a live run, and the user does the reload.
