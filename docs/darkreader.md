# Dark Reader

Moved from nowhere — new 2026-10-06; the project rules in CLAUDE.md still apply.

## Dark Reader follows the desktop palette, live

`scripts/darkreader-live.py` (+ `darkreader-live-patch.js`, tested by
`python3 scripts/test-darkreader-live.py`). Zen's own chrome is Pywalfox +
`update-zen-colors.sh`; this is the page content.

**Why a patched copy.** Measured against Dark Reader 4.9.133, not assumed:

- It takes settings only from its own popup/options pages. `Messenger` has an `onConnect`
  for its own ports and no `onConnectExternal` / `onMessageExternal`. Pywalfox's
  "Darkreader integration" (`runtime.connect("addon@darkreader.org")`) therefore reaches
  nothing, and its toggle is commented out in the settings UI.
- It never listens to `storage.onChanged` and rewrites its whole in-memory settings on any
  change, so writing its storage from outside only lands after a restart, and only if nothing
  saves first. (With `syncSettings` the theme is in `storage.sync`, not the IDB.)

So the one live route is code inside its background page. `build` patches the INSTALLED xpi
(same add-on id → same storage, same settings, full UI): `nativeMessaging` permission, version
`+.1`, `META-INF/` signature dropped, and `darkreader-live-patch.js` inserted after
`Messenger.init(...)`. It calls `Extension.setTheme` — the popup's own call — so every open tab
repaints. The anchor is Dark Reader's code: if an update moves it `build` exits with a message
rather than shipping a patch that does nothing; a rebuild from an already-patched xpi works.

**The pipe.** Zen spawns the host (`darkreader-live.py` with no subcommand, via a manifest in
`~/.mozilla/native-messaging-hosts/`) for as long as it runs. It binds
`$XDG_RUNTIME_DIR/quicktest-darkreader-<pid>.sock` and accepts only the word `push` — never a
colour; the palette always comes from `$XDG_CACHE_HOME/wal/colors.json`, the file every other
app step reads. `apps-lib.sh`'s `recolor_browser` runs `probe` then `push` right after
Pywalfox, so it happens under the wave's curtain like the rest. One socket per host: two
browsers can each have the patched extension.

**What it sets.** Background, foreground (`color7`) and `color1` as `selectionColor` — the
roles `update-zen-colors.sh` uses. The background is the palette's own, because that is what
Zen's sidebar and top bar wear: `userChrome.css` points them at `--lwt-accent-color`
(Pywalfox's frame). Measured from a screenshot (2026-10-06): sidebar and top bar `#000000` for
a `#000000` palette. **Don't "match the toolbar" with Pywalfox's `backgroundLight`
(`color0` +125%, `#172636 → #34567a`)**: it is in Pywalfox's theme state under `toolbar`, `sidebar`
and `popup`, which looks like what Zen shows, and was tried and was wrong — userChrome overrides
those surfaces. **Why pages still aren't exactly the sidebar's colour** (read from Dark Reader's
`modifyBgHSL`, confirmed by pixels): only a pure-white page background maps exactly to the
colour it is given. Every other shade keeps the page's own lightness hierarchy (a site's
off-white body lands near 12% lightness however dark the colour is), and NEUTRAL colours
borrow the given colour's hue and saturation. Exact needs `engine: staticTheme` — declined by
the user, who kept the dynamic engine. What is done instead: `tame()` caps the background's
HSL saturation at `MAX_SATURATION` (0.4), because HSL saturation is unstable near black —
`#0e0000` is "100% red" and tinted a whole page neon red beside a near-black sidebar. Hue and
lightness are kept; greys and muted colours are untouched.
A dark palette sets Dark Reader's dark scheme, a light one its light scheme;
the other scheme and the mode stay the user's. Both ends validate `#rrggbb`; the extension
also allowlists the keys.

**The host is a long-lived process**: a change to `darkreader-live.py` reaches Zen only when
the host restarts (kill it — the extension reconnects within a second and Zen respawns it —
or restart Zen).

**What it costs the user.**

- `xpinstall.signatures.required=false` in the profile's `user.js` (`install` sets it,
  `uninstall` sets it back). Zen's build has `MOZ_REQUIRE_SIGNING=false` (read from its
  omni.ja), so the pref is honoured and `distribution/policies.json` doesn't lock it. The cost
  is that the profile then accepts ANY unsigned extension.
- An AMO update would replace the patched copy: turn Automatic Updates off for Dark Reader in
  about:addons, and re-run `build` + reinstall when upgrading on purpose.

**Not verified.** Everything up to the browser boundary is tested (palette mapping, xpi patch
against the real 4.9.133 code, host over its stdio and socket, the patch's logic against
stubs). The pieces only a real Zen shows: that it loads the unsigned xpi over the signed one
keeping its settings, finds the host manifest, and that `setTheme` repaints open tabs.
