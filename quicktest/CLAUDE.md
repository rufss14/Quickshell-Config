# Quickshell Refactor

Full-codebase refactor of my Quickshell desktop shell (Arch + Hyprland, QML/JS).
You own the outcome, not just individual edits.

**Status lives in `~/.claude/plans/transient-zooming-minsky.md`** — that file is the
source of truth for what's done and what's open, not this one. Read it to resume.

## How to work
- Work in reviewable stages, not wholesale rewrites. After each: a brief summary of what
  changed and why, and flag anything only I can test (visual behavior, Hyprland IPC).
- Ask when it matters — ambiguous existing choices, intentional-vs-cruft, subjective
  design calls, anything expensive to redo if guessed wrong. Decide trivia yourself.
- **Never run build/reload/system-affecting commands without asking.** I reload the
  shell; you propose the command.
- When a task looks simple and well-scoped (searches, file surveys, mechanical edits,
  lint sweeps), offer to hand it to a Haiku subagent and let me confirm — don't spawn
  one silently. Keep design and architecture calls in the main thread.

## Standards
- **Colors only from the `Colors` palette singleton** (Material You, wallpaper-extracted),
  never hardcoded hex. Spacing, type scale, radii, motion durations/easing come from the
  shared `Tokens`/`Motion` — widgets consume them, never invent their own.
- Bar, launcher, notifications, OSD, lockscreen share one corner language, elevation
  logic, and motion personality.
- Separate presentation (QML) / logic (JS) / system integration (IPC, D-Bus). Theme and
  Hyprland connection are singletons/services, never reimplemented per-widget.
- Prefer event-driven Hyprland integration over polling.
- Lazy-load elements that aren't always visible (popups, overlays) instead of
  always-mounted-but-hidden. Watch for expensive bindings and per-frame work.
- Flag dead code before removing it, in case it's load-bearing.

## API caution
Quickshell is young and evolving. Don't assume API shape from training data — check
actual usage in this repo, and flag uncertainty rather than asserting confidently.

## Guardrails
- Don't edit `config.json` directly — the running shell owns it.
- Don't delete `config/settings/` (the friend's reference app) without asking.

## Tone
Casual for plans and tradeoffs; rigorous and precise in the actual code. Trivial stuff:
just do it. Structural or design-direction calls: explain why.
